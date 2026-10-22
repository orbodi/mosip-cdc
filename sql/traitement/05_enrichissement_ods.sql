-- =====================================================================
-- ODS : dernière réponse de l'API pour chaque dossier (connecteur ods-enrichissement).
-- Créée à l'avance pour que la vue directe la trouve avant la première réponse de l'API.
-- Mêmes champs que lake.mosip_prereg_enrichissement, sans aucune donnée nominative.
-- À exécuter une fois, en tant que ods_writer (aucun superuser nécessaire) :
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/05_enrichissement_ods.sql
-- publisher pourra la lire grâce aux droits par défaut définis à la création du schéma ods.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

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
