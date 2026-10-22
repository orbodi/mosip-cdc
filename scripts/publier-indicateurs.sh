#!/usr/bin/env bash
# Publie les dimensions et les indicateurs calculés par dbt vers les schémas ref et ind, lus par l'API.
# Tout est remplacé dans une seule transaction : l'API lit l'ancienne version jusqu'au COMMIT,
# sans jamais voir une table vide ni être bloquée.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGPASSWORD="$PUBLISHER_PASSWORD"

psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q <<'SQL'
BEGIN;
DELETE FROM ref.dim_date;
INSERT INTO ref.dim_date SELECT * FROM dwh.dim_date;
DELETE FROM ref.dim_statut;
INSERT INTO ref.dim_statut SELECT * FROM dwh.dim_statut;
DELETE FROM ind.ind_preinscription_jour;
INSERT INTO ind.ind_preinscription_jour SELECT * FROM dm_preinscription.ind_preinscription_jour;
COMMIT;
SQL
echo "$(date '+%F %T') publication terminée"
