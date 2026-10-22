#!/usr/bin/env bash
# Crée les topics écrits par Spark (Kafka refuse l'auto-création et Kafka Connect ne les crée pas).
# Peut être relancé sans risque (--if-not-exists).
set -euo pipefail
K="docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092"

# Dernier enrichissement de chaque dossier : compacté, Kafka garde la dernière valeur par prereg_id, sans limite de durée
$K --create --if-not-exists --topic mosip.prereg.enrichissement \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact

# Appels à l'API en échec, repris par le job de reprise : 28 jours, comme le topic des dossiers
$K --create --if-not-exists --topic mosip.prereg.enrichissement.erreurs \
   --partitions 1 --replication-factor 1 --config retention.ms=2419200000

$K --describe --topic mosip.prereg.enrichissement
$K --describe --topic mosip.prereg.enrichissement.erreurs
