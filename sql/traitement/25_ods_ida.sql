-- =====================================================================
-- ODS des authentifications (lot 9, 04/11/2026) : état courant de deux tables de mosip_ida, une ligne par clé MOSIP,
-- mise à jour sur place par les connecteurs ods-ida-auth-transaction et ods-ida-otp-transaction (upsert).
-- Relevé : docs/releve-authentification.md.
--
-- Noms : ods.ida_<table> (le connecteur JDBC cherche sa table par son nom dans tous les schémas, incident du
-- 25/10/2026 : aucune table du même nom ailleurs). Nom fixé par collection.name.format.
--
-- Créées à l'avance pour que dbt les trouve avant le premier message. Mêmes colonnes que celles qu'écrivent les
-- connecteurs (column.include.list de mosip-ida-cdc, champs ajoutés par ExtractNewRecordState et InsertField).
-- __kafka_offset : offset du message qui a écrit la ligne (une partition, une tâche : il suit l'ordre d'écriture).
--
-- Données personnelles : ref_id, token_id, static_tkn_id, les signatures (auth_transaction), ref_id et otp_hash
-- (otp_transaction) ne sont jamais captés. status_comment (messages fixes d'IDA) reste ici : seul un code de motif est
-- publié vers bi.
--
-- À exécuter une fois, en tant que ods_writer, AVANT de créer les connecteurs :
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/25_ods_ida.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS ods.ida_auth_transaction (
    id                      text      PRIMARY KEY,   -- clé technique (UUID)
    cr_dtimes               timestamp,               -- enregistrement de l'authentification (jour des indicateurs)
    auth_type_code          text,                    -- liste de modalités : FINGERPRINT-AUTH,IRIS-AUTH,OTP-AUTH…
    status_code             text,                    -- Y (réussie), N (échouée)
    status_comment          text,                    -- message d'IDA, rangé en motif par dbt (jamais publié)
    requested_entity_type   text,                    -- PARTNER ou INTERNAL
    requested_entity_id     text,                    -- appelant : partenaire (AU-ANID) ou client MOSIP
    requested_entity_name   text,                    -- nom déclaré dans MOSIP (organisation)
    is_deleted              boolean,
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS ida_auth_transaction_offset_idx ON ods.ida_auth_transaction (__kafka_offset);
CREATE INDEX IF NOT EXISTS ida_auth_transaction_cr_dtimes_idx ON ods.ida_auth_transaction (cr_dtimes);

CREATE TABLE IF NOT EXISTS ods.ida_otp_transaction (
    id                      text      PRIMARY KEY,   -- clé technique (UUID)
    status_code             text,                    -- active (jamais utilisé), used (utilisé)
    cr_dtimes               timestamp,               -- demande du code (generated_dtimes est vide dans MOSIP)
    expiry_dtimes           timestamp,               -- expiration du code
    is_deleted              boolean,
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS ida_otp_transaction_offset_idx ON ods.ida_otp_transaction (__kafka_offset);

-- Lecture par dbt ; publisher lit l'heure du dernier changement pour le contrôle de santé.
GRANT SELECT ON ods.ida_auth_transaction, ods.ida_otp_transaction TO dbt_runner;
GRANT SELECT ON ods.ida_auth_transaction, ods.ida_otp_transaction TO publisher;
