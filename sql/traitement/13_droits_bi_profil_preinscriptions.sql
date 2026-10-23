-- Publication du profil et du territoire des pré-inscriptions (tables créées par la migration V6 du backend).
-- À exécuter par bi_owner, après le démarrage de l'API qui a appliqué V6 :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/13_droits_bi_profil_preinscriptions.sql
\set ON_ERROR_STOP on
GRANT SELECT, INSERT, DELETE ON bi.fait_preinscription_profil_jour, bi.fait_preinscription_zone_jour TO publisher;
