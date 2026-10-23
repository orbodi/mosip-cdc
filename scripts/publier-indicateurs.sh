#!/usr/bin/env bash
# Publie les indicateurs calculés par dbt : contrat bi du tableau de bord (mosip-bi-reporting), puis ref et ind.
# Tout est remplacé dans une seule transaction : l'API lit l'ancienne version jusqu'au COMMIT,
# sans jamais voir une table vide ni être bloquée.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGCLIENTENCODING=UTF8
export PGPASSWORD="$PUBLISHER_PASSWORD"

psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q <<'SQL'
BEGIN;
-- Référentiel : bi.zone, niveau par niveau (le parent est déjà en place)
\set n region
\i sql/publication/zone_niveau.sql
\set n prefecture
\i sql/publication/zone_niveau.sql
\set n commune
\i sql/publication/zone_niveau.sql
\set n canton
\i sql/publication/zone_niveau.sql
\set n localite
\i sql/publication/zone_niveau.sql
\set n centre
\i sql/publication/zone_niveau.sql
-- Contrat du backend (tables créées par Flyway, propriétaire bi_owner)
DELETE FROM bi.fait_preinscription_jour;
INSERT INTO bi.fait_preinscription_jour (jour, statut, sexe, demandes, consommees)
SELECT jour, statut, sexe, demandes, consommees FROM dm_preinscription.fait_preinscription_jour;
INSERT INTO bi.source_fraicheur (source, libelle, ordre, premiere_donnee, derniere_donnee, dernier_chargement)
SELECT 'preinscription', 'Pré-inscription', 6, premiere_donnee, derniere_donnee, now()
FROM dm_preinscription.fraicheur_preinscription
ON CONFLICT (source) DO UPDATE
   SET premiere_donnee    = excluded.premiere_donnee,
       derniere_donnee    = excluded.derniere_donnee,
       dernier_chargement = excluded.dernier_chargement;
-- Schémas ref et ind (première version, plus lus par le tableau de bord)
DELETE FROM ref.dim_date;
INSERT INTO ref.dim_date SELECT * FROM dwh.dim_date;
DELETE FROM ref.dim_statut;
INSERT INTO ref.dim_statut (status_code, libelle, ordre, est_final)
SELECT status_code, libelle, ordre, est_final FROM dwh.dim_statut;
DELETE FROM ind.ind_preinscription_jour;
INSERT INTO ind.ind_preinscription_jour SELECT * FROM dm_preinscription.ind_preinscription_jour;
COMMIT;
SQL
echo "$(date '+%F %T') publication terminée"
