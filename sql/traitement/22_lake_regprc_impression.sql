-- =====================================================================
-- Data lake de l'impression (lot 8, 02/11/2026) : journal de regprc.printing_orders_details (connecteur
-- lake-regprc-printing-orders-details), une ligne par événement, jamais modifiée. Les événements de MOSIP ne sont eux
-- aussi jamais modifiés (relevé : 0 mise à jour). Environ 70 000 lignes par jour.
--
-- Le snapshot n'y met que les annulations (NEW-PRINT-CANCELED) et les erreurs d'envoi à l'IDPS (PRINT-REQUEST-ERR),
-- environ 300 000 lignes ; ensuite, tous les nouveaux événements arrivent. Les dates d'envoi, d'expédition et de
-- remise de l'historique viennent de l'ODS (21_ods_regprc_impression.sql). details (texte libre) et cr_by ne sont
-- jamais captés.
--
-- Créée à l'avance pour que dbt la trouve avant le premier message. À exécuter une fois, en tant que ingest_writer,
-- AVANT de créer le connecteur :
--   psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/22_lake_regprc_impression.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS lake.mosip_regprc_printing_orders_details (
    __connect_topic         text      NOT NULL,
    __connect_partition     integer   NOT NULL,
    __connect_offset        bigint    NOT NULL,
    id                      bigint,
    request_id              text,                    -- commande
    status_code             text,                    -- NEW-PRINT-REQUEST-RECEIVED … CARD-DELIVERED, PRINT-REQUEST-ERR
    reason_code             text,                    -- motif d'annulation (CANCEL_PHOTO…) ou code d'erreur
    sub_status_code         text,
    cr_dtimes               timestamp,               -- date de l'événement
    __deleted               text,
    __op                    text,
    __lsn                   bigint,
    __source_ts_ms          bigint,
    PRIMARY KEY (__connect_topic, __connect_partition, __connect_offset)
);
CREATE INDEX IF NOT EXISTS mosip_regprc_printing_orders_details_request_id_idx
    ON lake.mosip_regprc_printing_orders_details (request_id);

GRANT SELECT ON lake.mosip_regprc_printing_orders_details TO dbt_runner;
