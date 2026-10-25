-- =====================================================================
-- Index partiel du journal de rid_uin_link pour l'alerte « entry_date modifiée »
-- (dbt/tests/assert_rid_uin_link_date_modifiee.sql) : seulement les modifications (__op = 'u'), par date de source.
-- Sans lui, l'alerte relit tout le journal à chaque passage (79 s le 25/10/2026).
--
-- À exécuter une fois, en tant que ingest_writer (propriétaire de la table), à tout moment : CONCURRENTLY ne bloque
-- pas l'écriture du connecteur lake-regprc-rid-uin-link pendant la construction (quelques secondes).
--   psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/18_index_lake_regprc.sql
-- Sur une nouvelle installation, 15_lake_regprc.sql crée déjà cet index.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE INDEX CONCURRENTLY IF NOT EXISTS mosip_regprc_rid_uin_link_modif_idx
    ON lake.mosip_regprc_rid_uin_link (__source_ts_ms)
    WHERE __op = 'u';

-- Contrôle : l'index existe et est valide (indisvalid = t ; f si la construction a été interrompue : le supprimer
-- par DROP INDEX CONCURRENTLY lake.mosip_regprc_rid_uin_link_modif_idx, puis relancer ce script).
SELECT c.relname AS index, i.indisvalid AS valide, pg_size_pretty(pg_relation_size(c.oid)) AS taille
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relname = 'mosip_regprc_rid_uin_link_modif_idx';
