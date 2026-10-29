"""Rattrapage du stock : enrichit les dossiers qui n'ont pas encore de réponse de l'API.

Lancé par cron deux fois par jour, avec des débits différents (nuit : 32 appels/s, jour : 8).
Charge une seule fois la liste des dossiers à traiter depuis l'ODS (dossiers sans enrichissement,
les plus récents d'abord), puis la traite par paquets jusqu'à l'heure de fin. Chaque paquet est
publié aussitôt : un arrêt ne fait perdre que le paquet en cours. Le lendemain, le job reprend
naturellement là où il s'était arrêté, puisqu'il ne sélectionne que les dossiers encore sans réponse.

Exemple :
  spark-submit rattrapage_stock.py [--source prereg|inscriptions] --debit 32 --simultanes 16 --fin 05:00 \
      [--limite 200000]

Sources (commun/sources.py) : prereg (par défaut), pré-inscriptions sans réponse de l'API de pré-inscription ;
inscriptions, NIU générés (ods.regprc_rid_uin_link) sans réponse de l'ID Repository.
"""
import argparse
import datetime as dt
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor

from commun import config, publication
from commun.sources import SOURCES

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logging.getLogger("httpx").setLevel(logging.WARNING)

SEUIL_ERREURS = 0.10       # au-delà de 10 % d'échecs temporaires dans un paquet : pause
PAUSE_S = 300              # pause de 5 minutes
PAQUETS_MAUVAIS_MAX = 3    # 3 paquets mauvais d'affilée : arrêt


def journal(texte):
    print(f"{time.strftime('%F %T')} {texte}", flush=True)


def arguments(argv=None):
    p = argparse.ArgumentParser(description="Rattrapage de l'enrichissement des dossiers existants")
    p.add_argument("--source", choices=sorted(SOURCES), default="prereg", help="source enrichie (prereg par défaut)")
    p.add_argument("--debit", type=float, required=True, help="appels par seconde au maximum")
    p.add_argument("--simultanes", type=int, required=True, help="appels simultanés")
    p.add_argument("--fin", required=True, help="heure d'arrêt, HH:MM (heure du conteneur, UTC)")
    p.add_argument("--limite", type=int, default=0, help="nombre maximum de dossiers (0 : tous)")
    p.add_argument("--paquet", type=int, default=2000, help="dossiers publiés ensemble")
    return p.parse_args(argv)


def heure_de_fin(hhmm, maintenant=None):
    maintenant = maintenant or dt.datetime.now()
    heures, minutes = (int(x) for x in hhmm.split(":"))
    fin = maintenant.replace(hour=heures, minute=minutes, second=0, microsecond=0)
    return fin if fin > maintenant else fin + dt.timedelta(days=1)


def charger_ids(spark, requete, limite):
    requete = requete + (f" LIMIT {int(limite)}" if limite else "")
    df = (spark.read.format("jdbc")
          .option("url", config.TRAITEMENT_JDBC)
          .option("user", "spark_reader")
          .option("password", os.environ["SPARK_READER_PASSWORD"])
          .option("driver", "org.postgresql.Driver")
          .option("query", requete)
          .option("fetchsize", 10000)
          .load())
    return [r.id for r in df.collect()]


def rattraper(ids, enrichir, publier, simultanes, taille_paquet, fin,
              maintenant=dt.datetime.now, dormir=time.sleep, source=SOURCES["prereg"]):
    """Traite `ids` par paquets jusqu'à `fin`. Renvoie (traités, enrichis, échecs)."""
    traites = enrichis = echecs = 0
    mauvais_daffilee = 0
    t0 = time.monotonic()
    with ThreadPoolExecutor(max_workers=simultanes) as pool:
        for debut in range(0, len(ids), taille_paquet):
            if maintenant() >= fin:
                journal(f"heure de fin atteinte ({fin:%H:%M}) : arrêt, reprise au prochain lancement")
                break
            paquet = ids[debut:debut + taille_paquet]
            resultats = list(pool.map(enrichir, paquet))
            horodatage = int(time.time() * 1000)
            reussis = [r for r in resultats if r["ok"]]
            rates = [r for r in resultats if not r["ok"]]
            publier(source.topic_enrichi, source.format.enrichis(reussis, horodatage))
            publier(source.topic_erreurs, source.format.erreurs(rates, horodatage))
            traites += len(paquet)
            enrichis += len(reussis)
            echecs += len(rates)
            debit = traites / max(time.monotonic() - t0, 0.001)
            journal(f"{traites}/{len(ids)} traités, {enrichis} enrichis, {echecs} échecs, "
                    f"{debit:.1f} appels/s")

            temporaires = sum(1 for r in rates if not r.get("definitif"))
            if temporaires > SEUIL_ERREURS * len(paquet):
                mauvais_daffilee += 1
                if mauvais_daffilee >= PAQUETS_MAUVAIS_MAX:
                    journal(f"API en difficulté ({PAQUETS_MAUVAIS_MAX} paquets d'affilée avec plus de "
                            f"{SEUIL_ERREURS:.0%} d'échecs) : arrêt")
                    break
                journal(f"{temporaires} échecs temporaires sur {len(paquet)} : pause de {PAUSE_S // 60} min")
                dormir(PAUSE_S)
            else:
                mauvais_daffilee = 0
    return traites, enrichis, echecs


def main():
    from pyspark.sql import SparkSession

    a = arguments()
    source = SOURCES[a.source]
    fin = heure_de_fin(a.fin)
    nom_appli = "rattrapage-stock" if source.nom == "prereg" else f"rattrapage-{source.nom}"
    spark = SparkSession.builder.appName(nom_appli).getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    ids = charger_ids(spark, source.requete_rattrapage, a.limite)
    journal(f"début ({source.nom}) : {len(ids)} dossiers à enrichir, {a.debit:g} appels/s au maximum, "
            f"{a.simultanes} simultanés, arrêt à {fin:%F %H:%M}")
    if ids:
        client = source.client(debit_max=a.debit)
        traites, enrichis, echecs = rattraper(
            ids, client.enrichir, lambda topic, messages: publication.publier(spark, topic, messages),
            a.simultanes, a.paquet, fin, source=source)
        journal(f"fin : {traites} traités, {enrichis} enrichis, {echecs} échecs, "
                f"{len(ids) - traites} restants pour le prochain lancement")
    spark.stop()


if __name__ == "__main__":
    main()
