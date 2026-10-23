-- Prérequis sur mosip_master pour le connecteur Debezium du référentiel (mosip-master-cdc).
-- À exécuter UNE fois par un administrateur de la base MOSIP, connecté à mosip_master.

-- 1. Lecture des trois tables pour le snapshot initial du connecteur
GRANT CONNECT ON DATABASE mosip_master TO eidreporting;
GRANT USAGE ON SCHEMA master TO eidreporting;
GRANT SELECT ON master.location, master.registration_center, master.dynamic_field TO eidreporting;

-- 2. Battement de cœur : le référentiel change rarement ; sans écriture dans mosip_master, le slot n'avance pas
--    et retient les journaux (WAL) de tout le serveur. Le connecteur met à jour cette ligne toutes les minutes.
CREATE SCHEMA IF NOT EXISTS debezium;
CREATE TABLE IF NOT EXISTS debezium.heartbeat (id int PRIMARY KEY, ts timestamptz NOT NULL);
INSERT INTO debezium.heartbeat VALUES (1, now()) ON CONFLICT (id) DO NOTHING;
GRANT USAGE ON SCHEMA debezium TO eidreporting;
GRANT SELECT, UPDATE ON debezium.heartbeat TO eidreporting;

-- 3. Publication existante : master.location et master.dynamic_field y sont déjà ; ajouter les centres et le
--    battement de cœur
ALTER PUBLICATION dbz_publication ADD TABLE master.registration_center, debezium.heartbeat;

-- 4. Recommandé (postgresql.conf, puis rechargement) : plafond des journaux retenus par un slot en retard.
--    Au-delà, le slot est invalidé au lieu de remplir le disque du serveur MOSIP.
--    max_slot_wal_keep_size = '20GB'
