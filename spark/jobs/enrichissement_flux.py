"""Enrichissement en continu.

Toutes les 10 secondes, lit les nouveaux changements du topic des dossiers, appelle l'API pour
les dossiers créés ou modifiés, et publie les champs utiles dans le topic enrichi de la source
(les échecs dans son topic d'erreurs). N'écrit dans aucune base.
Démarre à la fin du topic : le stock existant est traité par le job de rattrapage.

  spark-submit enrichissement_flux.py [--source prereg|inscriptions]

- prereg (par défaut) : mosip.prereg.applicant_demographic → API de pré-inscription → mosip.prereg.enrichissement ;
- inscriptions : liens créés dans mosip.regprc.rid_uin_link (NIU générés) → ID Repository, appelé avec le RID →
  mosip.regprc.enrichissement.
"""
import argparse
import logging
import time
from concurrent.futures import ThreadPoolExecutor

from pyspark.sql import SparkSession, Window, functions as F

from commun import config, publication
from commun.sources import SOURCES

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)

spark = None
client = None
source = None


def decoder(messages, champ_id):
    """Une ligne par message : identifiant du dossier (id), opération Debezium, offset."""
    valeur = F.col("value").cast("string")
    return (messages
            .select(F.coalesce(F.get_json_object(valeur, f"$.payload.after.{champ_id}"),
                               F.get_json_object(valeur, f"$.payload.before.{champ_id}")).alias("id"),
                    F.get_json_object(valeur, "$.payload.op").alias("op"),
                    "offset")
            .where("id IS NOT NULL"))


def ids_a_enrichir(lot, operations):
    """Dernier événement de chaque dossier du lot ; seules les opérations de la source comptent (prereg : créations
    et modifications ; inscriptions : créations de lien)."""
    w = Window.partitionBy("id").orderBy(F.col("offset").desc())
    return [r.id for r in (lot.withColumn("rn", F.row_number().over(w))
                              .where(F.col("rn") == 1)
                              .where(F.col("op").isin(*operations))
                              .select("id").collect())]


def traiter(lot, lot_id):
    debut = time.monotonic()
    ids = ids_a_enrichir(lot, source.operations)
    if not ids:
        return
    with ThreadPoolExecutor(max_workers=config.FLUX_APPELS_SIMULTANES) as pool:
        resultats = list(pool.map(client.enrichir, ids))
    maintenant = int(time.time() * 1000)
    reussis = [r for r in resultats if r["ok"]]
    # Pendant une pause de refus d'accès (api_client), les dossiers ne sont pas appelés : ni publiés en erreur ;
    # ils seront repris par le rattrapage.
    echecs = [r for r in resultats if not r["ok"] and r.get("code_erreur") != "ACCES_REFUSE"]
    publication.publier(spark, source.topic_enrichi, source.format.enrichis(reussis, maintenant))
    publication.publier(spark, source.topic_erreurs, source.format.erreurs(echecs, maintenant))
    print(f"{time.strftime('%F %T')} lot {lot_id} : {len(ids)} dossiers, {len(reussis)} enrichis, "
          f"{len(echecs)} échecs, {time.monotonic() - debut:.1f} s", flush=True)


def arguments(argv=None):
    p = argparse.ArgumentParser(description="Enrichissement en continu")
    p.add_argument("--source", choices=sorted(SOURCES), default="prereg", help="source enrichie (prereg par défaut)")
    return p.parse_args(argv)


def main():
    global spark, client, source
    source = SOURCES[arguments().source]
    nom_appli = "enrichissement-flux" if source.nom == "prereg" else f"enrichissement-{source.nom}-flux"
    spark = SparkSession.builder.appName(nom_appli).getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    client = source.client(debit_max=config.FLUX_DEBIT_MAX)

    messages = (spark.readStream.format("kafka")
                .option("kafka.bootstrap.servers", config.KAFKA)
                .option("subscribe", source.topic_entree)
                .option("startingOffsets", "latest")
                .option("maxOffsetsPerTrigger", config.FLUX_MAX_MESSAGES_PAR_LOT)
                .option("failOnDataLoss", "false")      # messages expirés : rattrapés par le job de rattrapage
                .load())

    (decoder(messages, source.champ_id).writeStream
        .foreachBatch(traiter)
        .option("checkpointLocation", f"{config.CHECKPOINTS}/{source.point_de_reprise}")
        .trigger(processingTime=config.FLUX_INTERVALLE)
        .start()
        .awaitTermination())


if __name__ == "__main__":
    main()
