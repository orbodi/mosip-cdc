-- Lot 8d (NIU sans commande d'impression) : table créée par la migration V16 du backend. La colonne erreurs_idps de
-- bi.fait_demande_impression_jour (V16 aussi) n'a pas besoin de droit de plus (23_droits_bi_impression.sql).
-- À exécuter par bi_owner, APRÈS le démarrage de l'API qui a appliqué V16, AVANT le git pull de mosip-cdc qui publie
-- cette table (relançable : GRANT est idempotent) :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/24_droits_bi_impression_8d.sql
\set ON_ERROR_STOP on
GRANT SELECT, INSERT, DELETE ON bi.stock_niu_sans_commande TO publisher;
