-- Rôle propriétaire du contrat du tableau de bord (schémas bi, etat, pipeline créés par Flyway au
-- démarrage de l'API mosip-bi-reporting). À exécuter UNE fois, par un rôle autorisé à créer des rôles :
--   psql -h 172.16.44.108 -U <admin> -d mosip_bi -v mdp="$BI_OWNER_PASSWORD" -f sql/traitement/08_role_bi_owner.sql
\set ON_ERROR_STOP on

CREATE ROLE bi_owner LOGIN PASSWORD :'mdp';
GRANT CREATE ON DATABASE mosip_bi TO bi_owner;

-- Mode PostgreSQL standard pour le backend : DATE reste une date, 'a' || NULL = NULL.
ALTER ROLE bi_owner   SET edb_redwood_date = off;
ALTER ROLE bi_owner   SET edb_redwood_strings = off;
ALTER ROLE api_reader SET edb_redwood_date = off;
ALTER ROLE api_reader SET edb_redwood_strings = off;
