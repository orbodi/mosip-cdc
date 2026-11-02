-- =====================================================================
-- ODS de l'impression et de la remise des cartes (lot 8, 02/11/2026) : état courant de deux tables de mosip_regprc,
-- une ligne par clé MOSIP, mise à jour sur place par les connecteurs ods-regprc-printing-orders et
-- ods-regprc-printing-shipped-cards (upsert). Relevé : docs/releve-impression.md.
--
-- Noms : ods.regprc_<table>, distincts de ceux du lake (lake.mosip_regprc_<table>) : le connecteur JDBC cherche sa
-- table par son nom dans tous les schémas (incident du 25/10/2026). Nom fixé par collection.name.format.
--
-- Créées à l'avance pour que dbt les trouve avant le premier message. Mêmes colonnes que celles qu'écrivent les
-- connecteurs (column.include.list de mosip-regprc-impression-cdc, champs ajoutés par ExtractNewRecordState et
-- InsertField). __kafka_offset : offset du message qui a écrit la ligne (une partition, une tâche : il suit l'ordre
-- d'écriture, dbt ne relit que les lignes plus récentes que son dernier passage).
--
-- Données personnelles : uin, citizen_fingers_count, center_name (commandes) ; serial_number, logical_number,
-- tracking_number, box_number, delivered_by, has_finger_biometrics_exception (cartes) ne sont jamais captés. Le RID et
-- request_id sont en clair ici, comme dans l'ODS de l'enrôlement ; ils ne sont jamais publiés vers bi.
--
-- À exécuter une fois, en tant que ods_writer, AVANT de créer les connecteurs :
--   psql -h 172.16.44.108 -U ods_writer -d mosip_bi -f sql/traitement/21_ods_regprc_impression.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS ods.regprc_printing_orders (
    id                      bigint    PRIMARY KEY,   -- clé technique
    rid                     text,                    -- RID : centre d'enrôlement et lien avec le NIU
    request_id              text,                    -- commande : lien avec l'historique et la carte
    prc_status              text,                    -- NEW (en attente), OK (envoyée à l'imprimeur), KO (rejetée)
    entry_date              timestamp,               -- réception de la commande
    issuing_date            timestamp,               -- envoi à l'imprimeur
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS regprc_printing_orders_offset_idx ON ods.regprc_printing_orders (__kafka_offset);
CREATE INDEX IF NOT EXISTS regprc_printing_orders_request_id_idx ON ods.regprc_printing_orders (request_id);
CREATE INDEX IF NOT EXISTS regprc_printing_orders_rid_idx ON ods.regprc_printing_orders (rid);

CREATE TABLE IF NOT EXISTS ods.regprc_printing_shipped_cards (
    id                      bigint    PRIMARY KEY,   -- clé technique
    request_id              text,                    -- commande
    entry_date              timestamp,               -- expédition (mise en boîte)
    delivery_status         text,                    -- DELIVERED ou NOT_DELIVERED
    delivery_mode           text,                    -- OFFLINE, ONLINE, SUPPORT ; vide si non remise
    delivery_date           timestamp,               -- remise au citoyen
    __deleted               text,
    __op                    text,
    __source_ts_ms          bigint,
    __kafka_offset          bigint
);
CREATE INDEX IF NOT EXISTS regprc_printing_shipped_cards_offset_idx
    ON ods.regprc_printing_shipped_cards (__kafka_offset);
CREATE INDEX IF NOT EXISTS regprc_printing_shipped_cards_request_id_idx
    ON ods.regprc_printing_shipped_cards (request_id);

-- Lecture par dbt ; publisher lit l'heure du dernier changement pour le contrôle de santé.
GRANT SELECT ON ods.regprc_printing_orders, ods.regprc_printing_shipped_cards TO dbt_runner;
GRANT SELECT ON ods.regprc_printing_orders, ods.regprc_printing_shipped_cards TO publisher;
