"""Configuration des jobs Spark, lue dans les variables d'environnement (fichier compose/.env)."""
import os

KAFKA = os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092")
TOPIC_DOSSIERS = "mosip.prereg.applicant_demographic"
TOPIC_ENRICHI = "mosip.prereg.enrichissement"
TOPIC_ERREURS = "mosip.prereg.enrichissement.erreurs"
CHECKPOINTS = os.environ.get("SPARK_CHECKPOINTS", "/checkpoints")

# API de pré-inscription MOSIP
API_URL = os.environ["API_URL"].rstrip("/")
API_APP_ID = os.environ["API_APP_ID"]
API_CLIENT_ID = os.environ["API_CLIENT_ID"]
API_SECRET_KEY = os.environ["API_SECRET_KEY"]
API_CA_FILE = os.environ.get("API_CA_FILE", "/certs/ca-eid.crt")
# Vérification du certificat de l'API : désactivée par défaut, true quand compose/certs/ca-eid.crt est en place
API_TLS_VERIFY = os.environ.get("API_TLS_VERIFY", "false").strip().lower() == "true"
API_DELAI_S = float(os.environ.get("API_DELAI_S", "10"))          # délai maximum d'un appel
API_ESSAIS = int(os.environ.get("API_ESSAIS", "3"))                # tentatives avant de déclarer un échec
JETON_RENOUVELLEMENT_S = int(os.environ.get("API_JETON_RENOUVELLEMENT_S", "32400"))  # 9 h (jeton valable 10 h)

# BD traitement : le rattrapage y lit l'ODS (rôle spark_reader)
TRAITEMENT_JDBC = f"jdbc:postgresql://{os.environ.get('TRAITEMENT_PG_HOST', 'localhost')}:5432/mosip_bi"

# Job en continu : les nouveaux dossiers sont peu nombreux, un faible débit suffit
FLUX_APPELS_SIMULTANES = int(os.environ.get("FLUX_APPELS_SIMULTANES", "4"))
FLUX_DEBIT_MAX = float(os.environ.get("FLUX_DEBIT_MAX", "5"))     # appels par seconde
FLUX_INTERVALLE = os.environ.get("FLUX_INTERVALLE", "10 seconds")
FLUX_MAX_MESSAGES_PAR_LOT = int(os.environ.get("FLUX_MAX_MESSAGES_PAR_LOT", "2000"))
