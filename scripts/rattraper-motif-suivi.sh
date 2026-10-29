#!/usr/bin/env bash
# Écrit le code du motif de MOSIP (V11, décision du 29/10/2026) dans les dossiers DÉJÀ publiés de bi.suivi_dossier.
# La publication des 5 minutes ne reprend que les dossiers modifiés (maj_le) : sans ce rattrapage, un dossier arrêté
# avant la mise en service n'aurait pas de motif. À lancer à la main :
#   - une fois, après le premier passage qui publie la colonne motif (V11 appliquée, droits 16 relancés) ;
#   - après un changement des règles du catalogue (seeds/ref_regprc_motifs.csv, colonne regle) qui range autrement
#     des commentaires déjà publiés. Un changement de libellé seul n'en a pas besoin (bi.ref_motif, à chaque passage).
# Ne touche que les dossiers dont le motif change (≈ 350 000 dossiers sans NIU la première fois, quelques-uns ensuite).
# Prend le verrou de la chaîne analytique : aucun passage dbt ni publication ne tourne pendant le rattrapage.
#
#   scripts/rattraper-motif-suivi.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGCLIENTENCODING=UTF8
export PGPASSWORD="$PUBLISHER_PASSWORD"
[ -n "${SUIVI_HMAC_CLE:-}" ] || { echo "SUIVI_HMAC_CLE absente de compose/.env" >&2; exit 1; }

exec 9>/tmp/mosip-analytique.lock
echo "$(date '+%F %T') attente du verrou de la chaîne analytique…"
flock 9
echo "$(date '+%F %T') rattrapage du motif dans le suivi d'un dossier"

# La clé passe par un paramètre de session (bi.cle_suivi) : elle n'apparaît ni à l'écran ni dans l'historique.
psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q -v cle_suivi="$SUIVI_HMAC_CLE" <<'SQL'
SELECT set_config('bi.cle_suivi', :'cle_suivi', false) \gset ignore_
-- Dossiers avec un motif dans dm_enrolement (rejetés, échoués, en cours) dont le motif publié diffère.
WITH source AS (
    SELECT hmac(s.rid, current_setting('bi.cle_suivi'), 'sha256') AS empreinte, s.motif
    FROM dm_enrolement.suivi_dossier s
    WHERE s.motif IS NOT NULL
),
ecrit AS (
    UPDATE bi.suivi_dossier d
    SET motif = source.motif
    FROM source
    WHERE d.empreinte = source.empreinte
      AND d.motif IS DISTINCT FROM source.motif
    RETURNING 1
)
SELECT count(*) AS dossiers_mis_a_jour FROM ecrit;
SELECT count(*) FILTER (WHERE motif IS NOT NULL) AS dossiers_avec_motif,
       count(*) FILTER (WHERE motif IS NULL AND devenir IN ('rejete', 'echoue', 'en_cours')) AS sans_niu_sans_motif
FROM bi.suivi_dossier;
SQL
echo "$(date '+%F %T') rattrapage terminé"
