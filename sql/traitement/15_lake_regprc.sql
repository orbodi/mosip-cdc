-- =====================================================================
-- Data lake de l'enrôlement : journal de regprc.rid_uin_link (connecteur lake-regprc-rid-uin-link), une ligne par
-- changement, jamais modifiée. Sert à repérer les liens dont entry_date change après coup (relevé, étape 4 : la table
-- est mise à jour environ 2,5 fois par ligne, sans qu'on sache quelles colonnes). Environ 35 000 lignes par jour.
--
-- registration et registration_list n'ont pas de journal : leur état courant suffit (ODS, 14_ods_regprc.sql), et
-- registration reçoit environ 610 000 mises à jour par jour.
--
-- Créée à l'avance pour que dbt la trouve avant le premier message. À exécuter une fois, en tant que ingest_writer :
--   psql -h 172.16.44.108 -U ingest_writer -d mosip_bi -f sql/traitement/15_lake_regprc.sql
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS lake.mosip_regprc_rid_uin_link (
    __connect_topic         text      NOT NULL,
    __connect_partition     integer   NOT NULL,
    __connect_offset        bigint    NOT NULL,
    id                      bigint,
    reg_id                  text,
    reg_type                text,
    entry_date              timestamp,
    __deleted               text,
    __op                    text,
    __lsn                   bigint,
    __source_ts_ms          bigint,
    PRIMARY KEY (__connect_topic, __connect_partition, __connect_offset)
);
CREATE INDEX IF NOT EXISTS mosip_regprc_rid_uin_link_reg_id_idx ON lake.mosip_regprc_rid_uin_link (reg_id);

GRANT SELECT ON lake.mosip_regprc_rid_uin_link TO dbt_runner;
