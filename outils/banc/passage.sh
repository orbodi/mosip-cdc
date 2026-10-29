#!/usr/bin/env bash
# Un passage de la chaîne analytique sur le banc : mini dbt (dbt build) puis le VRAI scripts/publier-indicateurs.sh,
# lancé depuis une copie temporaire du dépôt avec un compose/.env de test (jamais celui du serveur).
#
#   outils/banc/passage.sh [--full-refresh] [--sans-publication]
set -euo pipefail
CDC=$(cd "$(dirname "$0")/../.." && pwd)
HOTE=${PGHOST:-/tmp}
JOURNAL=$(mktemp)
DBT_ARGS=()
[[ " $* " == *" --full-refresh "* ]] && DBT_ARGS+=(--full-refresh)

if python3 "$CDC/outils/banc/minidbt.py" "$CDC/dbt" "host=$HOTE dbname=mosip_bi user=dbt_runner" "${DBT_ARGS[@]}" \
     > "$JOURNAL" 2>&1; then statut=0; else statut=$?; fi
grep -E "^modèle .*(regprc|suivi|enrolement|niu_jour|niu_profil|centre_region|arret|stock|delai)|ÉCHEC|ALERTE|tests :|Error" "$JOURNAL" || true
[ "$statut" -eq 0 ] || { echo "dbt en échec : rien n'est publié (journal : $JOURNAL)"; exit "$statut"; }
[[ " $* " == *" --sans-publication "* ]] && exit 0

COPIE=$(mktemp -d)
cp -r "$CDC/scripts" "$CDC/sql" "$COPIE/"
mkdir "$COPIE/compose"
printf 'TRAITEMENT_PG_HOST=%s\nPUBLISHER_PASSWORD=banc\nSUIVI_HMAC_CLE=%s\n' "$HOTE" "${SUIVI_HMAC_CLE-cle-du-banc}" \
  > "$COPIE/compose/.env"
bash "$COPIE/scripts/publier-indicateurs.sh"
rm -rf "$COPIE"
