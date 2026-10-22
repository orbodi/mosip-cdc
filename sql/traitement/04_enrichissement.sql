-- =====================================================================
-- Tables d'enrichissement, créées à l'avance pour que dbt et la vue directe les trouvent
-- avant la première réponse de l'API. Structure identique à celle que créeraient les connecteurs.
-- Seuls les champs utiles de l'API sont stockés : jamais les noms, le téléphone,
-- la date de naissance complète ni le lieu de naissance.
-- À exécuter une fois, en superuser :
--   psql -h 172.16.44.108 -U enterprisedb -d mosip_bi -f sql/traitement/04_enrichissement.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

-- Data lake : une ligne par réponse de l'API (connecteur lake-enrichissement)
SET ROLE ingest_writer;
CREATE TABLE IF NOT EXISTS lake.mosip_prereg_enrichissement (
    __connect_topic      text      NOT NULL,
    __connect_partition  integer   NOT NULL,
    __connect_offset     bigint    NOT NULL,
    prereg_id            text      NOT NULL,
    genre                text,
    nationalite          text,
    annee_naissance      integer,
    mois_naissance       integer,
    region_code          text,
    prefecture_code      text,
    commune_code         text,
    canton_code          text,
    localite_code        text,
    api_statut           integer,
    enrichi_le           timestamp NOT NULL,
    PRIMARY KEY (__connect_topic, __connect_partition, __connect_offset)
);
RESET ROLE;

-- ODS : dernière réponse de chaque dossier (connecteur ods-enrichissement)
SET ROLE ods_writer;
CREATE TABLE IF NOT EXISTS ods.enrichissement (
    prereg_id            text      PRIMARY KEY,
    genre                text,
    nationalite          text,
    annee_naissance      integer,
    mois_naissance       integer,
    region_code          text,
    prefecture_code      text,
    commune_code         text,
    canton_code          text,
    localite_code        text,
    api_statut           integer,
    enrichi_le           timestamp NOT NULL
);
RESET ROLE;
