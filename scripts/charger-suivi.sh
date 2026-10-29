#!/usr/bin/env bash
# Charge (ou recharge) en entier bi.suivi_dossier, par lots de 500 000 lignes validés un à un, hors de la transaction
# de publication des 5 minutes. À lancer à la main :
#   - une fois, à la mise en service du suivi d'un dossier (≈ 6,4 M de lignes) ;
#   - après un dbt --full-refresh de suivi_inscription, ou un changement de SUIVI_HMAC_CLE (dans ce cas, vider
#     d'abord la table : les anciennes empreintes ne correspondent plus à rien).
# Prend le verrou de la chaîne analytique : aucun passage dbt ni publication ne tourne pendant le chargement.
#
#   scripts/charger-suivi.sh [--vider]
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGCLIENTENCODING=UTF8
export PGPASSWORD="$PUBLISHER_PASSWORD"
[ -n "${SUIVI_HMAC_CLE:-}" ] || { echo "SUIVI_HMAC_CLE absente de compose/.env" >&2; exit 1; }
VIDER=false
[ "${1:-}" = "--vider" ] && VIDER=true

exec 9>/tmp/mosip-analytique.lock
echo "$(date '+%F %T') attente du verrou de la chaîne analytique…"
flock 9
echo "$(date '+%F %T') chargement du suivi d'un dossier"

# La clé passe par un paramètre de session (bi.cle_suivi), lu dans le bloc DO : elle n'apparaît ni à l'écran ni dans
# l'historique. Chaque lot est validé (COMMIT) : une interruption garde les lots déjà chargés ; relancer reprend tout.
psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q -v cle_suivi="$SUIVI_HMAC_CLE" \
     -v vider="$VIDER" <<'SQL'
SELECT set_config('bi.cle_suivi', :'cle_suivi', false) \gset ignore_
\if :vider
DELETE FROM bi.suivi_dossier;
\endif
DO $$
DECLARE
    dernier  text := '';
    n        bigint;
    total    bigint := 0;
BEGIN
    LOOP
        WITH lot AS (
            SELECT * FROM dm_enrolement.suivi_dossier WHERE rid > dernier ORDER BY rid LIMIT 500000
        ),
        ecrit AS (
            INSERT INTO bi.suivi_dossier (empreinte, centre_id, type_demande, enrole_le, synchronise_le, refus_poste,
                                          recu_le, niu_le, devenir, etape, etape_libelle, etape_statut,
                                          derniere_transaction_le, motif, maj_le)
            SELECT hmac(s.rid, current_setting('bi.cle_suivi'), 'sha256'), coalesce(z.id, h.id), s.type_demande,
                   s.enrole_le, s.synchronise_le, s.refus_poste, s.recu_le, s.niu_le, s.devenir, s.etape,
                   s.etape_libelle, s.etape_statut, s.derniere_transaction_le, s.motif, s.maj_le
            FROM lot s
            CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
            LEFT JOIN bi.zone z ON z.code = s.code_centre AND z.niveau = 'centre'
            ON CONFLICT (empreinte) DO UPDATE
               SET centre_id = excluded.centre_id, type_demande = excluded.type_demande,
                   enrole_le = excluded.enrole_le, synchronise_le = excluded.synchronise_le,
                   refus_poste = excluded.refus_poste, recu_le = excluded.recu_le, niu_le = excluded.niu_le,
                   devenir = excluded.devenir, etape = excluded.etape, etape_libelle = excluded.etape_libelle,
                   etape_statut = excluded.etape_statut, derniere_transaction_le = excluded.derniere_transaction_le,
                   motif = excluded.motif, maj_le = excluded.maj_le
            RETURNING 1
        )
        SELECT count(*), max(rid) INTO n, dernier FROM lot WHERE (SELECT count(*) FROM ecrit) >= 0;
        EXIT WHEN n = 0;
        total := total + n;
        COMMIT;
        RAISE NOTICE '% lignes chargées', total;
    END LOOP;
END
$$;
SELECT count(*) AS lignes, max(maj_le) AS derniere_maj FROM bi.suivi_dossier;
SQL
echo "$(date '+%F %T') chargement terminé"
