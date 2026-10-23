-- =====================================================================
-- Rôle de lecture du job de rattrapage : il lit l'ODS pour trouver les dossiers sans enrichissement.
-- Partie 1, structure : en superuser, une seule fois.
--   psql -h 172.16.44.108 -U enterprisedb -d mosip_bi -v mdp="'<mot de passe>'" -f sql/traitement/06_role_spark_reader.sql
-- =====================================================================
\set ON_ERROR_STOP on
CREATE ROLE spark_reader LOGIN PASSWORD :mdp;
GRANT USAGE ON SCHEMA ods TO spark_reader;
