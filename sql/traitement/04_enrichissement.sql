-- =====================================================================
-- Data lake : table d'enrichissement, une ligne par réponse de l'API (connecteur lake-enrichissement).
-- Créée à l'avance pour que dbt la trouve avant la première réponse de l'API.
-- Seuls les champs utiles de l'API sont stockés : jamais les noms, le téléphone,
-- la date de naissance complète ni le lieu de naissance.
-- À exécuter une fois, en tant que ingest_writer (aucun superuser nécessaire) :
--   psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/04_enrichissement.sql
-- dbt_runner pourra la lire grâce aux droits par défaut définis à la création du schéma lake.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

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
