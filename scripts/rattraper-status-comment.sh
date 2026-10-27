#!/usr/bin/env bash
# Rattrapage unique de ods.regprc_registration.status_comment (27/10/2026).
# Le connecteur mosip-regprc-cdc ne transmet status_comment que depuis le 27/10/2026 : les inscriptions captées avant
# et non modifiées depuis ont la colonne vide. Ce script la remplit pour les inscriptions qui peuvent avoir un motif
# (status_code <> 'PROCESSED' : rejetées, échouées, en cours), en lisant mosip_regprc avec le compte du connecteur.
# - Copie de base à base par un tube, sans fichier intermédiaire (le RID ne quitte pas les bases).
# - N'écrase jamais une valeur déjà écrite par le connecteur (plus récente) : seules les lignes vides sont remplies.
# - Sans effet sur __kafka_offset : dbt range les commentaires en motifs en relisant l'ODS à chaque passage.
# Relançable sans risque. Demande le mot de passe de ods_writer.
#
#   scripts/rattraper-status-comment.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGCLIENTENCODING=UTF8
[ -n "${MOSIP_PG_HOST:-}" ] && [ -n "${MOSIP_PG_PASSWORD:-}" ] \
  || { echo "MOSIP_PG_HOST et MOSIP_PG_PASSWORD absents de compose/.env" >&2; exit 1; }

echo "$(date '+%F %T') lecture de mosip_regprc et mise à jour de l'ODS…"
PGPASSWORD="$MOSIP_PG_PASSWORD" psql -h "$MOSIP_PG_HOST" -U eidreporting -d mosip_regprc -X -q -v ON_ERROR_STOP=1 \
  -c "\copy (SELECT id, status_comment FROM regprc.registration WHERE status_code <> 'PROCESSED' AND status_comment IS NOT NULL) TO STDOUT" |
psql -h "$TRAITEMENT_PG_HOST" -U ods_writer -d mosip_bi -X -v ON_ERROR_STOP=1 \
  -c "CREATE TEMP TABLE rattrapage (id text PRIMARY KEY, status_comment text)" \
  -c "\copy rattrapage FROM PSTDIN" \
  -c "SELECT count(*) AS lues_dans_mosip FROM rattrapage" \
  -c "UPDATE ods.regprc_registration o SET status_comment = r.status_comment
      FROM rattrapage r WHERE o.id = r.id AND o.status_comment IS NULL" \
  -c "SELECT count(*) FILTER (WHERE status_comment IS NOT NULL) AS avec_commentaire,
             count(*) FILTER (WHERE status_comment IS NULL AND status_code <> 'PROCESSED') AS encore_vides_hors_processed
      FROM ods.regprc_registration"
echo "$(date '+%F %T') terminé"
