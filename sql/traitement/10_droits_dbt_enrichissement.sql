-- Lecture des enrichissements par dbt (modèle stg_prereg__enrichissement). À exécuter par ingest_writer :
--   PGPASSWORD=... psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/10_droits_dbt_enrichissement.sql
\set ON_ERROR_STOP on
GRANT SELECT ON lake.mosip_prereg_enrichissement TO dbt_runner;
