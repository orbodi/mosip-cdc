-- Publication des authentifications dans le contrat bi (tables créées par la migration V17 du backend, lot 9).
-- À exécuter par bi_owner, APRÈS le démarrage de l'API qui a appliqué V17, AVANT le git pull de mosip-cdc qui publie
-- ces tables (relançable : GRANT est idempotent) :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/26_droits_bi_authentification.sql
-- api_reader lit déjà toutes les tables de bi (privilèges par défaut de 09_droits_bi.sql).
\set ON_ERROR_STOP on
-- Faits et libellés remplacés à chaque passage par pg_temp.synchroniser (seulement les lignes qui changent)
GRANT SELECT, INSERT, DELETE ON bi.fait_authentification_jour, bi.fait_demande_otp_jour, bi.fait_code_otp_jour,
                                bi.ref_motif_authentification TO publisher;
