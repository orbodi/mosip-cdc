-- Publication de l'enrôlement dans le contrat bi (tables créées par les migrations V1 à V3 et V7 du backend).
-- À exécuter par bi_owner, APRÈS le démarrage de l'API qui a appliqué V7 :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/16_droits_bi_enrolement.sql
\set ON_ERROR_STOP on
GRANT SELECT, INSERT, DELETE ON bi.fait_enrolement_jour, bi.fait_niu_jour TO publisher;
-- V7 : faits et stocks remplacés à chaque passage ; suivi d'un dossier mis à jour par upsert
GRANT SELECT, INSERT, DELETE ON bi.fait_arret_etape_jour, bi.stock_en_cours, bi.fait_delai_jour,
                                bi.stock_synchro_non_recue, bi.fait_niu_nationalite_jour TO publisher;
GRANT SELECT, INSERT, UPDATE, DELETE ON bi.suivi_dossier TO publisher;   -- DELETE : charger-suivi.sh --vider
