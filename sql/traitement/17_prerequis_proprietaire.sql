-- Prérequis de l'enrôlement sur mosip_bi, réservés au propriétaire de la base et des schémas lake et ods
-- (enterprisedb, relevé du 25/10/2026). À exécuter une fois, AVANT 14_ods_regprc.sql et 15_lake_regprc.sql :
--   psql -h 172.16.44.108 -U enterprisedb -d mosip_bi -f sql/traitement/17_prerequis_proprietaire.sql
\set ON_ERROR_STOP on

-- 1. Extension pgcrypto : fonction hmac() de l'empreinte du RID (suivi d'un dossier, bi.suivi_dossier).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Lecture du schéma ods par dbt (nouveau : l'enrôlement est lu dans l'ODS) ; publisher le lit déjà (indicateurs
--    en direct des pré-inscriptions). Les droits sur les tables sont donnés par 14_ods_regprc.sql.
GRANT USAGE ON SCHEMA ods TO dbt_runner, publisher;

-- 3. Contrôles : les connecteurs créent ou modifient leurs tables (schema.evolution) dans leur schéma
SELECT extname, extversion FROM pg_extension WHERE extname = 'pgcrypto';
SELECT has_schema_privilege('ods_writer', 'ods', 'CREATE')       AS ods_writer_cree_dans_ods,
       has_schema_privilege('ingest_writer', 'lake', 'CREATE')   AS ingest_writer_cree_dans_lake,
       has_schema_privilege('dbt_runner', 'ods', 'USAGE')        AS dbt_lit_ods,
       has_schema_privilege('dbt_runner', 'lake', 'USAGE')       AS dbt_lit_lake;
-- La clé HMAC passe en paramètre des requêtes de publication : vérifier qu'elles ne sont pas journalisées
SHOW log_statement;   -- attendu : none ou ddl (relevé du 25/10/2026 : none)
