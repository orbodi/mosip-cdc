-- =====================================================================
-- Data lake : enrichissement des inscriptions qui ont un NIU (connecteur lake-regprc-enrichissement, lot 6), une
-- ligne par réponse de l'ID Repository, jamais modifiée. Clé : RID. Seuls le genre, la nationalité, l'année et le
-- mois de naissance sont stockés : jamais le NIU, les noms, le téléphone, la pièce d'identité, la date de naissance
-- complète ni les lieux.
-- Créée à l'avance pour que dbt la trouve avant la première réponse de l'API.
-- À exécuter une fois, en tant que ingest_writer :
--   psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/19_lake_regprc_enrichissement.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS lake.mosip_regprc_enrichissement (
    __connect_topic      text      NOT NULL,
    __connect_partition  integer   NOT NULL,
    __connect_offset     bigint    NOT NULL,
    rid                  text      NOT NULL,
    genre                text,
    nationalite          text,
    annee_naissance      integer,
    mois_naissance       integer,
    api_statut           integer,
    enrichi_le           timestamp NOT NULL,
    PRIMARY KEY (__connect_topic, __connect_partition, __connect_offset)
);
-- Lecture incrémentale par dbt (stg_regprc__enrichissement) : par offset
CREATE INDEX IF NOT EXISTS mosip_regprc_enrichissement_offset_idx ON lake.mosip_regprc_enrichissement (__connect_offset);

GRANT SELECT ON lake.mosip_regprc_enrichissement TO dbt_runner;
