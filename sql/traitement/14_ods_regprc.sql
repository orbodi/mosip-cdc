-- =====================================================================
-- ODS de l'enrôlement : état courant de trois tables de mosip_regprc, une ligne par clé MOSIP, mise à jour sur place
-- par les connecteurs ods-regprc-registration, ods-regprc-rid-uin-link et ods-regprc-registration-list (upsert).
--
-- Noms : ods.regprc_<table>, distincts de ceux du lake (lake.mosip_regprc_<table>), comme ods.applicant_demographic
-- pour les pré-inscriptions. Le connecteur JDBC cherche sa table par son nom dans tous les schémas : avec le même nom
-- dans ods et lake, il écrivait dans le lake (incident du 25/10/2026). Nom fixé par collection.name.format.
--
-- Créées à l'avance pour que dbt les trouve avant le premier message : sans elles, dbt build échoue et plus rien
-- n'est publié, pré-inscriptions comprises. Mêmes colonnes que celles qu'écrivent les connecteurs (column.include.list
-- de mosip-regprc-cdc, champs ajoutés par ExtractNewRecordState et InsertField).
-- __kafka_offset : offset du message qui a écrit la ligne. Chaque topic n'a qu'une partition et chaque connecteur
-- qu'une tâche, donc l'offset suit l'ordre d'écriture : dbt ne relit que les lignes plus récentes que son dernier
-- passage.
--
-- Données personnelles : uin et civil_registry_number (rid_uin_link) ne sont jamais captés ; aucun nom, téléphone ni
-- adresse de registration_list. Le RID (id, reg_id) est en clair ici, comme le prereg_id ; il n'est jamais publié
-- vers bi.
--
-- À exécuter une fois, en tant que ods_writer, APRÈS 17_prerequis_proprietaire.sql (usage du schéma ods) :
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/14_ods_regprc.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS ods.regprc_registration (
    id                      text      PRIMARY KEY,   -- RID
    reg_type                text,
    status_code             text,
    latest_trn_type_code    text,
    latest_trn_status_code  text,
    latest_trn_dtimes       timestamp,
    reg_stage_name          text,
    cr_dtimes               timestamp,               -- réception par MOSIP
    upd_dtimes              timestamp,
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS regprc_registration_offset_idx ON ods.regprc_registration (__kafka_offset);

CREATE TABLE IF NOT EXISTS ods.regprc_rid_uin_link (
    id                      bigint    PRIMARY KEY,   -- clé technique, sans valeur métier
    reg_id                  text,                    -- RID
    reg_type                text,
    entry_date              timestamp,               -- génération du NIU (relevé, étape 3)
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS regprc_rid_uin_link_offset_idx ON ods.regprc_rid_uin_link (__kafka_offset);
CREATE INDEX IF NOT EXISTS regprc_rid_uin_link_reg_id_idx ON ods.regprc_rid_uin_link (reg_id);

CREATE TABLE IF NOT EXISTS ods.regprc_registration_list (
    id                      text      PRIMARY KEY,   -- clé de la synchronisation
    reg_id                  text,                    -- RID
    reg_type                text,
    client_status_code      text,                    -- APPROVED ou REJECTED (décision du poste)
    cr_dtimes               timestamp,               -- synchronisation
    upd_dtimes              timestamp,
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS regprc_registration_list_offset_idx
    ON ods.regprc_registration_list (__kafka_offset);
CREATE INDEX IF NOT EXISTS regprc_registration_list_reg_id_idx ON ods.regprc_registration_list (reg_id);

-- Lecture par dbt ; publisher lit l'heure du dernier changement pour le contrôle de santé (scripts/check-health.sh).
-- L'usage du schéma ods est donné par son propriétaire (17_prerequis_proprietaire.sql).
GRANT SELECT ON ods.regprc_registration, ods.regprc_rid_uin_link, ods.regprc_registration_list
    TO dbt_runner;
GRANT SELECT ON ods.regprc_registration TO publisher;
