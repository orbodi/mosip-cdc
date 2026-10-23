#!/usr/bin/env bash
# Contrôle de santé du pipeline, lancé toutes les 5 minutes par cron. N'affiche rien quand tout va bien.
# Chaque alerte est affichée (cron l'envoie par e-mail si MAILTO et un agent de messagerie sont
# configurés) et ajoutée à /var/log/mosip-bi/alertes.log.
set -u
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
mkdir -p /var/log/mosip-bi
ALERTES=/var/log/mosip-bi/alertes.log
alerte() { echo "ALERTE $*"; echo "$(date '+%F %T') $*" >> "$ALERTES"; }

# 1. Connecteurs Kafka Connect : connecteur et tâches en RUNNING
for c in mosip-prereg-cdc lake-prereg ods-prereg lake-enrichissement ods-enrichissement; do
  etat=$(curl -s --max-time 10 "http://localhost:8083/connectors/$c/status" \
    | jq -r '([.connector.state] + [.tasks[].state]) | unique | join(",")' 2>/dev/null)
  [ "$etat" = "RUNNING" ] || alerte "connecteur $c : ${etat:-injoignable}"
done

# 1b. Job Spark d'enrichissement en continu : conteneur en marche
[ "$(docker inspect -f '{{.State.Running}}' mosip-cdc-spark 2>/dev/null)" = "true" ] \
  || alerte "job Spark d'enrichissement (mosip-cdc-spark) arrêté"

# 2. Fraîcheur des indicateurs lus par l'API (âge en minutes du dernier calcul)
age() {
  PGPASSWORD="$PUBLISHER_PASSWORD" psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -Atq \
    -c "SELECT coalesce((extract(epoch FROM now() - max(calcule_le)) / 60)::int, 9999) FROM $1" 2>/dev/null
}
a=$(age ind.ind_preinscription_jour)
[ "${a:-9999}" -lt 45 ] || alerte "indicateurs d'analyse publiés il y a ${a:-?} min (attendu : moins de 45)"
d=$(age ind.ind_preinscription_direct)
[ "${d:-9999}" -lt 5 ]  || alerte "indicateurs en direct calculés il y a ${d:-?} min (attendu : moins de 5)"

# 3. Retard du slot de réplication sur MOSIP, si l'accès est renseigné dans compose/.env
if [ -n "${MOSIP_PG_HOST:-}" ] && [ -n "${MOSIP_PG_PASSWORD:-}" ]; then
  r=$(PGPASSWORD="$MOSIP_PG_PASSWORD" psql -h "$MOSIP_PG_HOST" -U eidreporting -d mosip_prereg -Atq -c \
    "SELECT (pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) / 1048576)::int
     FROM pg_replication_slots WHERE slot_name = 'mosip_applicant_cdc'" 2>/dev/null)
  if [ -z "$r" ]; then
    alerte "slot mosip_applicant_cdc introuvable ou MOSIP injoignable"
  elif [ "$r" -ge 1024 ]; then
    alerte "retard du slot mosip_applicant_cdc : $r Mo (attendu : moins de 1024)"
  fi
fi

# 4. Disque du serveur pipeline
p=$(df --output=pcent /data 2>/dev/null | tail -1 | tr -dc '0-9')
[ "${p:-0}" -lt 80 ] || alerte "disque /data occupé à $p % (attendu : moins de 80)"
