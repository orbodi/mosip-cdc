-- =====================================================================
-- ODS : dernière réponse de l'ID Repository pour chaque inscription qui a un NIU (connecteur ods-regprc-enrichissement,
-- lot 6). Mêmes champs que lake.mosip_regprc_enrichissement, sans aucune donnée nominative.
-- Lue par le rattrapage (spark_reader) pour retrouver les NIU encore sans réponse.
-- Créée à l'avance pour que le rattrapage la trouve avant la première réponse de l'API.
-- À exécuter une fois, en tant que ods_writer :
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/20_ods_regprc_enrichissement.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS ods.regprc_enrichissement (
    rid                  text      PRIMARY KEY,
    genre                text,
    nationalite          text,
    annee_naissance      integer,
    mois_naissance       integer,
    api_statut           integer,
    enrichi_le           timestamp NOT NULL
);

-- Rattrapage : liens NIU (ods.regprc_rid_uin_link, sans le NIU) et réponses déjà reçues
GRANT SELECT ON ods.regprc_rid_uin_link, ods.regprc_enrichissement TO spark_reader;
