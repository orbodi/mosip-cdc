-- =====================================================================
-- Rôle de lecture du job de rattrapage. Partie 2, droits sur les tables :
-- en tant que ods_writer, propriétaire des tables de l'ODS (aucun superuser nécessaire).
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/07_droits_spark_reader.sql
-- =====================================================================
\set ON_ERROR_STOP on
GRANT SELECT ON ods.applicant_demographic, ods.enrichissement TO spark_reader;
