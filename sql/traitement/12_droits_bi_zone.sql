-- Publication du référentiel dans bi.zone (scripts/publier-indicateurs.sh). À exécuter par bi_owner :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/12_droits_bi_zone.sql
\set ON_ERROR_STOP on
GRANT SELECT, INSERT, UPDATE ON bi.zone TO publisher;
