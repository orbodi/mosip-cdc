-- =====================================================================
-- Tables lues par l'API (schémas ref et ind) et indicateurs en direct.
-- À exécuter une fois, en tant que publisher, après le premier dbt build :
--   psql -h 172.16.44.108 -U publisher -d mosip_bi -f sql/traitement/03_publication.sql
-- Chaque table publiée copie la structure de sa source dbt, colonne par colonne.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

-- Dimensions
CREATE TABLE IF NOT EXISTS ref.dim_date   (LIKE dwh.dim_date);
CREATE TABLE IF NOT EXISTS ref.dim_statut (LIKE dwh.dim_statut);
ALTER TABLE ref.dim_date   DROP CONSTRAINT IF EXISTS dim_date_pkey;
ALTER TABLE ref.dim_date   ADD CONSTRAINT dim_date_pkey PRIMARY KEY (date_key);
ALTER TABLE ref.dim_statut DROP CONSTRAINT IF EXISTS dim_statut_pkey;
ALTER TABLE ref.dim_statut ADD CONSTRAINT dim_statut_pkey PRIMARY KEY (status_code);

-- Indicateurs d'analyse : un jour de création et une langue par ligne
CREATE TABLE IF NOT EXISTS ind.ind_preinscription_jour (LIKE dm_preinscription.ind_preinscription_jour);
CREATE UNIQUE INDEX IF NOT EXISTS ind_preinscription_jour_uk
    ON ind.ind_preinscription_jour (date_jour, langue);

-- Première publication, pour que la vue directe trouve les libellés des statuts
BEGIN;
DELETE FROM ref.dim_statut;
INSERT INTO ref.dim_statut SELECT * FROM dwh.dim_statut;
COMMIT;

-- Indicateurs en direct : dossiers par statut, en ce moment (rafraîchis chaque minute)
CREATE MATERIALIZED VIEW IF NOT EXISTS ind.ind_preinscription_direct AS
SELECT
    coalesce(p.status_code, 'INCONNU')                                       AS status_code,
    coalesce(s.libelle, p.status_code, 'Inconnu')                            AS statut,
    s.ordre,
    count(*)                                                                 AS nb_dossiers,
    count(*) FILTER (WHERE p.cr_dtimes >= date_trunc('day', now() AT TIME ZONE 'UTC'))
                                                                             AS nb_crees_aujourdhui,
    now()                                                                    AS calcule_le
FROM ods.applicant_demographic p
LEFT JOIN ref.dim_statut s ON s.status_code = p.status_code
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX IF NOT EXISTS ind_preinscription_direct_uk
    ON ind.ind_preinscription_direct (status_code);
