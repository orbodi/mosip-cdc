"""Enrichissement en continu.

Toutes les 10 secondes, lit les nouveaux changements du topic des dossiers, appelle l'API pour
les dossiers créés ou modifiés, et publie les champs utiles dans mosip.prereg.enrichissement
(les échecs dans mosip.prereg.enrichissement.erreurs). N'écrit dans aucune base.
Démarre à la fin du topic : le stock existant est traité par le job de rattrapage.
"""
import logging
import time
from concurrent.futures import ThreadPoolExecutor

from pyspark.sql import SparkSession, Window, functions as F

from commun import config, publication
from commun.api_client import ClientApi

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)

spark = None
client = None


def decoder(messages):
    """Une ligne par message : prereg_id, opération Debezium, offset."""
    valeur = F.col("value").cast("string")
    return (messages
            .select(F.coalesce(F.get_json_object(valeur, "$.payload.after.prereg_id"),
                               F.get_json_object(valeur, "$.payload.before.prereg_id")).alias("prereg_id"),
                    F.get_json_object(valeur, "$.payload.op").alias("op"),
                    "offset")
            .where("prereg_id IS NOT NULL"))


def ids_a_enrichir(lot):
    """Dernier événement de chaque dossier du lot ; seules les créations (c) et modifications (u) comptent."""
    w = Window.partitionBy("prereg_id").orderBy(F.col("offset").desc())
    return [r.prereg_id for r in (lot.withColumn("rn", F.row_number().over(w))
                                     .where("rn = 1 AND op IN ('c', 'u')")
                                     .select("prereg_id").collect())]


def traiter(lot, lot_id):
    debut = time.monotonic()
    ids = ids_a_enrichir(lot)
    if not ids:
        return
    with ThreadPoolExecutor(max_workers=config.FLUX_APPELS_SIMULTANES) as pool:
        resultats = list(pool.map(client.enrichir, ids))
    maintenant = int(time.time() * 1000)
    reussis = [r for r in resultats if r["ok"]]
    echecs = [r for r in resultats if not r["ok"]]
    publication.publier(spark, config.TOPIC_ENRICHI, publication.messages_enrichis(reussis, maintenant))
    publication.publier(spark, config.TOPIC_ERREURS, publication.messages_erreurs(echecs, maintenant))
    print(f"{time.strftime('%F %T')} lot {lot_id} : {len(ids)} dossiers, {len(reussis)} enrichis, "
          f"{len(echecs)} échecs, {time.monotonic() - debut:.1f} s", flush=True)


def main():
    global spark, client
    spark = SparkSession.builder.appName("enrichissement-flux").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    client = ClientApi(debit_max=config.FLUX_DEBIT_MAX)

    messages = (spark.readStream.format("kafka")
                .option("kafka.bootstrap.servers", config.KAFKA)
                .option("subscribe", config.TOPIC_DOSSIERS)
                .option("startingOffsets", "latest")
                .option("maxOffsetsPerTrigger", config.FLUX_MAX_MESSAGES_PAR_LOT)
                .option("failOnDataLoss", "false")      # messages expirés : rattrapés par le job de rattrapage
                .load())

    (decoder(messages).writeStream
        .foreachBatch(traiter)
        .option("checkpointLocation", f"{config.CHECKPOINTS}/enrichissement-flux")
        .trigger(processingTime=config.FLUX_INTERVALLE)
        .start()
        .awaitTermination())


if __name__ == "__main__":
    main()
