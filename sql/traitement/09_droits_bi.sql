-- Droits sur le contrat bi, APRÈS le premier démarrage de l'API (Flyway a créé les tables).
-- À exécuter par bi_owner :
--   PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/09_droits_bi.sql
\set ON_ERROR_STOP on

-- API : lecture seule du schéma bi (jamais etat ni pipeline), tables actuelles et futures.
GRANT USAGE ON SCHEMA bi TO api_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA bi TO api_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA bi GRANT SELECT ON TABLES TO api_reader;

-- Publication (scripts/publier-indicateurs.sh) : seulement les tables alimentées.
GRANT USAGE ON SCHEMA bi TO publisher;
GRANT SELECT, INSERT, DELETE ON bi.fait_preinscription_jour TO publisher;
GRANT SELECT, INSERT, UPDATE ON bi.source_fraicheur TO publisher;
