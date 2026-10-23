#!/usr/bin/env bash
# Crée les topics écrits par Spark et par le connecteur du référentiel (Kafka refuse l'auto-création).
# Peut être relancé sans risque (--if-not-exists).
set -euo pipefail
K="docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092"

# Dernier enrichissement de chaque dossier : compacté, Kafka garde la dernière valeur par prereg_id, sans limite de durée
$K --create --if-not-exists --topic mosip.prereg.enrichissement \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact

# Appels à l'API en échec, repris par le job de reprise : 28 jours, comme le topic des dossiers
$K --create --if-not-exists --topic mosip.prereg.enrichissement.erreurs \
   --partitions 1 --replication-factor 1 --config retention.ms=2419200000

# Référentiel MOSIP (connecteur mosip-master-cdc) : compactés, le topic garde toujours l'état complet par clé
$K --create --if-not-exists --topic mosip.master.location \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact
$K --create --if-not-exists --topic mosip.master.registration_center \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact
$K --create --if-not-exists --topic mosip.master.dynamic_field \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact
# Battements de cœur du connecteur (fait avancer le slot quand le référentiel ne change pas)
$K --create --if-not-exists --topic __debezium-heartbeat.mosip_master \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact

$K --describe --topic mosip.prereg.enrichissement
$K --describe --topic mosip.prereg.enrichissement.erreurs
$K --describe --topic mosip.master.location
$K --describe --topic mosip.master.registration_center
