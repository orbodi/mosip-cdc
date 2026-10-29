#!/usr/bin/env bash
# Crée les topics écrits par Spark et par les connecteurs du référentiel et de l'enrôlement (Kafka refuse
# l'auto-création).
# Peut être relancé sans risque (--if-not-exists).
set -euo pipefail
K="docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092"

# Dernier enrichissement de chaque dossier : compacté, Kafka garde la dernière valeur par prereg_id, sans limite de durée
$K --create --if-not-exists --topic mosip.prereg.enrichissement \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact

# Appels à l'API en échec, repris par le job de reprise : 28 jours, comme le topic des dossiers
$K --create --if-not-exists --topic mosip.prereg.enrichissement.erreurs \
   --partitions 1 --replication-factor 1 --config retention.ms=2419200000

# Enrichissement des inscriptions qui ont un NIU (ID Repository, lot 6) : comme celui des pré-inscriptions, dernière
# réponse de chaque RID dans un topic compacté, échecs gardés 28 jours
$K --create --if-not-exists --topic mosip.regprc.enrichissement \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact
$K --create --if-not-exists --topic mosip.regprc.enrichissement.erreurs \
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

# Enrôlement (connecteur mosip-regprc-cdc), UNE partition par topic : l'ordre des offsets suit l'ordre des changements,
# et les modèles dbt lisent l'ODS par offset.
# - registration et registration_list : compactés, Kafka garde le dernier état de chaque inscription sans limite de
#   durée, ce qui permet de reconstruire l'ODS. min.compaction.lag.ms laisse un jour aux connecteurs pour tout lire
#   avant compaction.
# - rid_uin_link : 28 jours, comme les autres journaux ; le lake (lake-regprc-rid-uin-link) garde tout l'historique.
$K --create --if-not-exists --topic mosip.regprc.registration \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact --config min.compaction.lag.ms=86400000
$K --create --if-not-exists --topic mosip.regprc.registration_list \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact --config min.compaction.lag.ms=86400000
$K --create --if-not-exists --topic mosip.regprc.rid_uin_link \
   --partitions 1 --replication-factor 1 --config retention.ms=2419200000
$K --create --if-not-exists --topic __debezium-heartbeat.mosip_regprc \
   --partitions 1 --replication-factor 1 --config cleanup.policy=compact

$K --describe --topic mosip.prereg.enrichissement
$K --describe --topic mosip.prereg.enrichissement.erreurs
$K --describe --topic mosip.regprc.registration
$K --describe --topic mosip.regprc.registration_list
$K --describe --topic mosip.regprc.rid_uin_link
$K --describe --topic mosip.regprc.enrichissement
$K --describe --topic mosip.regprc.enrichissement.erreurs
$K --describe --topic mosip.master.location
$K --describe --topic mosip.master.registration_center
