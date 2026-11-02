-- Prérequis sur mosip_regprc pour le connecteur Debezium de l'impression et de la remise des cartes
-- (mosip-regprc-impression-cdc, lot 8). À exécuter par un administrateur de la base MOSIP, connecté à mosip_regprc.
-- Partie A : contrôles en lecture seule, sans effet. Partie B : commandes à exécuter UNE fois, après relecture.
--   psql -h <serveur MOSIP> -U <dba> -d mosip_regprc -X -f sql/mosip/05_prerequis_impression.sql
-- (la partie B est en commentaire : la décommenter, ou la copier, après relecture de la partie A)
--
-- Relevé et décisions : docs/releve-impression.md (02/11/2026). Trois tables, seulement les colonnes sans identité :
--   regprc.printing_orders         : id, rid, request_id, prc_status, entry_date, issuing_date ;
--   regprc.printing_orders_details : id, request_id, status_code, reason_code, sub_status_code, cr_dtimes ;
--   regprc.printing_shipped_cards  : id, request_id, entry_date, delivery_status, delivery_mode, delivery_date.
-- Jamais lues : printing_orders.uin (NIU), citizen_fingers_count (biométrie), center_name ;
-- printing_orders_details.details (texte libre), cr_by ; printing_shipped_cards.serial_number, logical_number,
-- tracking_number, box_number (carte et colis), delivered_by (agent), has_finger_biometrics_exception (biométrie),
-- delivery_site (centre du RID). printing_processing_jobs et la vue printing_orders_status ne sont pas captées.
\set ON_ERROR_STOP on

-- =====================================================================================================
-- A. Contrôles (lecture seule)
-- =====================================================================================================
SHOW wal_level;                       -- attendu : logical
SHOW max_replication_slots;           -- un slot libre de plus que les slots existants (nouveau slot)
SHOW max_wal_senders;                 -- idem

-- Colonnes captées présentes, avec leur type (18 lignes attendues)
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'regprc'
  AND ((table_name = 'printing_orders'
        AND column_name IN ('id', 'rid', 'request_id', 'prc_status', 'entry_date', 'issuing_date'))
    OR (table_name = 'printing_orders_details'
        AND column_name IN ('id', 'request_id', 'status_code', 'reason_code', 'sub_status_code', 'cr_dtimes'))
    OR (table_name = 'printing_shipped_cards'
        AND column_name IN ('id', 'request_id', 'entry_date', 'delivery_status', 'delivery_mode', 'delivery_date')))
ORDER BY table_name, column_name;

-- Replica identity : DEFAULT (d) suffit, chaque table a une clé primaire (id)
SELECT c.relname, c.relreplident,
       (SELECT string_agg(a.attname, ', ')
        FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
        WHERE i.indrelid = c.oid AND i.indisprimary) AS cle_primaire
FROM pg_class c
WHERE c.oid IN ('regprc.printing_orders'::regclass, 'regprc.printing_orders_details'::regclass,
                'regprc.printing_shipped_cards'::regclass);

-- Les trois tables figurent dans dbz_publication (relevé du 02/11/2026 : oui)
SELECT pubname, schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'dbz_publication' AND schemaname = 'regprc' AND tablename LIKE 'printing%'
ORDER BY tablename;

-- Slots existants et leur retard (Mo) : le nouveau slot s'appellera mosip_regprc_impression_cdc
SELECT slot_name, plugin, database, active,
       (pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) / 1048576)::int AS retard_mo
FROM pg_replication_slots;

-- Lignes lues par le snapshot (environ 12,5 M) : commandes et cartes en entier, historique réduit aux annulations et
-- aux erreurs d'envoi (les dates d'envoi, d'expédition et de remise sont dans les deux autres tables).
SELECT 'printing_orders' AS table_lue, count(*) FROM regprc.printing_orders
UNION ALL
SELECT 'printing_shipped_cards', count(*) FROM regprc.printing_shipped_cards
UNION ALL
SELECT 'printing_orders_details (annulations, erreurs)', count(*) FROM regprc.printing_orders_details
WHERE status_code IN ('NEW-PRINT-CANCELED', 'PRINT-REQUEST-ERR');

-- =====================================================================================================
-- B. Commandes (une fois)
-- =====================================================================================================
-- B1. Lecture limitée aux colonnes captées (le snapshot ne lit que celles-ci). eidreporting a déjà l'attribut
--     REPLICATION et l'usage du schéma regprc (02_prerequis_regprc.sql).
-- GRANT SELECT (id, rid, request_id, prc_status, entry_date, issuing_date)
--     ON regprc.printing_orders TO eidreporting;
-- GRANT SELECT (id, request_id, status_code, reason_code, sub_status_code, cr_dtimes)
--     ON regprc.printing_orders_details TO eidreporting;
-- GRANT SELECT (id, request_id, entry_date, delivery_status, delivery_mode, delivery_date)
--     ON regprc.printing_shipped_cards TO eidreporting;

-- B2. Publication : rien à faire, les trois tables sont déjà dans dbz_publication. Le connecteur crée son propre slot
--     (mosip_regprc_impression_cdc) à son démarrage. La publication transmet toutes les colonnes au slot ; Debezium ne
--     garde que column.include.list, donc uin, details ou serial_number n'entrent jamais dans Kafka.

-- B3. Pas de table de battement de cœur : dbz_publication contient aussi registration (≈ 610 000 mises à jour par
--     jour) ; Debezium reçoit ces changements, les écarte (table.include.list) et fait avancer le slot à chaque
--     battement (heartbeat.interval.ms). Le slot n'est pas borné (EDB 12 : pas de max_slot_wal_keep_size) : son retard
--     est surveillé par scripts/check-health.sh, comme les trois autres.

-- B4. Snapshot initial : ≈ 12,5 M de lignes lues (6,2 M printing_orders, 6,1 M printing_shipped_cards, ≈ 0,3 M
--     printing_orders_details). Créneau creux convenu avec l'équipe BI ; le snapshot démarre dès la création du
--     connecteur.

-- Retour arrière (connecteur supprimé d'abord, côté Kafka Connect) :
-- SELECT pg_drop_replication_slot('mosip_regprc_impression_cdc');
-- REVOKE SELECT ON regprc.printing_orders, regprc.printing_orders_details, regprc.printing_shipped_cards
--     FROM eidreporting;
