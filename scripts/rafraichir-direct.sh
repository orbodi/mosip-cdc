#!/usr/bin/env bash
# Recalcule les indicateurs en direct à partir de l'ODS. CONCURRENTLY : l'API continue de lire
# l'ancienne version pendant le calcul.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGPASSWORD="$PUBLISHER_PASSWORD"
psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q \
  -c "REFRESH MATERIALIZED VIEW CONCURRENTLY ind.ind_preinscription_direct;"
