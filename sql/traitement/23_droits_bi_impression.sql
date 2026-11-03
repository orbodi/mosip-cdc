-- Publication de l'impression des cartes dans le contrat bi (tables créées par la migration V15 du backend, lot 8).
-- À exécuter par bi_owner, APRÈS le démarrage de l'API qui a appliqué V15, AVANT le git pull de mosip-cdc qui publie
-- ces tables (relançable : GRANT est idempotent) :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/23_droits_bi_impression.sql
-- api_reader lit déjà toutes les tables de bi (privilèges par défaut de 09_droits_bi.sql).
\set ON_ERROR_STOP on
-- Faits remplacés à chaque passage par pg_temp.synchroniser (seulement les lignes qui changent)
GRANT SELECT, INSERT, DELETE ON bi.fait_demande_impression_jour, bi.fait_carte_jour, bi.fait_delai_carte_jour,
                                bi.fait_annulation_impression_jour TO publisher;
