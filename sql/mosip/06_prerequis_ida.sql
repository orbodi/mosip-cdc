-- Prérequis sur mosip_ida pour le connecteur Debezium des authentifications (mosip-ida-cdc, lot 9).
-- À exécuter par un administrateur de la base MOSIP, connecté à mosip_ida.
-- Partie A : contrôles en lecture seule, sans effet. Partie B : commandes à exécuter UNE fois, après relecture.
--   psql -h <serveur MOSIP> -U <dba> -d mosip_ida -X -f sql/mosip/06_prerequis_ida.sql
-- (la partie B est en commentaire : la décommenter, ou la copier, après relecture de la partie A)
--
-- Relevé et décisions : docs/releve-authentification.md (03 et 04/11/2026). Deux tables seulement (décision du
-- responsable), et seulement les colonnes sans identité :
--   ida.auth_transaction : id, cr_dtimes, auth_type_code, status_code, status_comment, requested_entity_type,
--                          requested_entity_id, requested_entity_name, is_deleted ;
--   ida.otp_transaction  : id, status_code, cr_dtimes, expiry_dtimes, is_deleted.
-- status_comment : messages fixes d'IDA (« Finger Authentication Failed », codes IDA-BIA-006, IDA-MLC-018…), sans
-- long nombre ni donnée de personne sur 30 jours (relevé, requêtes 7 et 8) ; le texte reste dans l'ODS, seul un code
-- de motif est publié.
-- Jamais lues : ref_id (référence de l'individu), token_id et static_tkn_id (jetons de la personne), request_signature,
-- response_signature, request_trn_id, request_dtimes, response_dtimes, lang_code, ref_id_type, cr_by, upd_by,
-- upd_dtimes, del_dtimes (auth_transaction) ; ref_id, otp_hash, generated_dtimes, validation_retry_count, lang_code,
-- cr_by, upd_by, upd_dtimes, del_dtimes (otp_transaction). Aucune autre table de mosip_ida (identity_cache contient
-- les identités et la biométrie : jamais lue, même pour un comptage).
\set ON_ERROR_STOP on

-- =====================================================================================================
-- A. Contrôles (lecture seule)
-- =====================================================================================================
SHOW wal_level;                       -- attendu : logical
SHOW max_replication_slots;           -- un slot libre de plus que les slots existants (nouveau slot)
SHOW max_wal_senders;                 -- idem

-- Colonnes captées présentes, avec leur type (14 lignes attendues)
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ida'
  AND ((table_name = 'auth_transaction'
        AND column_name IN ('id', 'cr_dtimes', 'auth_type_code', 'status_code', 'status_comment',
                            'requested_entity_type', 'requested_entity_id', 'requested_entity_name', 'is_deleted'))
    OR (table_name = 'otp_transaction'
        AND column_name IN ('id', 'status_code', 'cr_dtimes', 'expiry_dtimes', 'is_deleted')))
ORDER BY table_name, column_name;

-- Replica identity : DEFAULT (d) suffit, chaque table a une clé primaire (id)
SELECT c.relname, c.relreplident,
       (SELECT string_agg(a.attname, ', ')
        FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
        WHERE i.indrelid = c.oid AND i.indisprimary) AS cle_primaire
FROM pg_class c
WHERE c.oid IN ('ida.auth_transaction'::regclass, 'ida.otp_transaction'::regclass);

-- Publications de mosip_ida (une publication appartient à une base : dbz_publication de mosip_regprc ne sert pas ici)
SELECT p.pubname, p.puballtables, pt.schemaname, pt.tablename
FROM pg_publication p LEFT JOIN pg_publication_tables pt ON pt.pubname = p.pubname
ORDER BY 1, 3, 4;

-- Droits actuels d'eidreporting sur la base et le schéma
SELECT has_database_privilege('eidreporting', 'mosip_ida', 'CONNECT') AS connexion,
       has_schema_privilege('eidreporting', 'ida', 'USAGE') AS usage_ida;

-- Slots existants et leur retard (Mo) : le nouveau slot s'appellera mosip_ida_cdc
SELECT slot_name, plugin, database, active,
       (pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) / 1048576)::int AS retard_mo
FROM pg_replication_slots;

-- Activité par heure sur 7 jours (index de cr_dtimes, sans lire la table) : s'il y a des heures sans aucune
-- authentification, le slot reste immobile pendant ces heures (voir B3)
SELECT extract(hour FROM cr_dtimes)::int AS heure, count(*) AS transactions
FROM ida.auth_transaction
WHERE cr_dtimes >= now() - interval '7 days'
GROUP BY 1 ORDER BY 1;

-- Lignes lues par le snapshot : estimation des statistiques (un count(*) parcourrait les 12 Go de auth_transaction)
SELECT c.relname, c.reltuples::bigint AS lignes_estimees, pg_size_pretty(pg_total_relation_size(c.oid)) AS taille
FROM pg_class c
WHERE c.oid IN ('ida.auth_transaction'::regclass, 'ida.otp_transaction'::regclass);
-- relevé du 03/11/2026 : ≈ 3 250 000 (12 Go) et ≈ 83 900 (31 Mo)

-- =====================================================================================================
-- B. Commandes (une fois)
-- =====================================================================================================
-- B1. Lecture limitée aux colonnes captées (le snapshot ne lit que celles-ci). eidreporting a déjà l'attribut
--     REPLICATION (connecteurs des autres bases).
-- GRANT CONNECT ON DATABASE mosip_ida TO eidreporting;
-- GRANT USAGE ON SCHEMA ida TO eidreporting;
-- GRANT SELECT (id, cr_dtimes, auth_type_code, status_code, status_comment, requested_entity_type,
--               requested_entity_id, requested_entity_name, is_deleted)
--     ON ida.auth_transaction TO eidreporting;
-- GRANT SELECT (id, status_code, cr_dtimes, expiry_dtimes, is_deleted)
--     ON ida.otp_transaction TO eidreporting;

-- B2. Publication. Le connecteur attend une publication nommée dbz_publication dans mosip_ida, avec les deux tables.
--     Si le contrôle de la partie A n'en montre aucune :
-- CREATE PUBLICATION dbz_publication FOR TABLE ida.auth_transaction, ida.otp_transaction;
--     Si dbz_publication existe déjà sans ces tables (elle sert peut-être à d'autres : à voir avec son propriétaire) :
-- ALTER PUBLICATION dbz_publication ADD TABLE ida.auth_transaction, ida.otp_transaction;
--     La publication transmet toutes les colonnes au slot (EDB 12 : pas de liste de colonnes) ; Debezium ne garde que
--     column.include.list, donc ref_id, token_id, les signatures et otp_hash n'entrent jamais dans Kafka.
--     Le connecteur crée son propre slot (mosip_ida_cdc) à son démarrage.

-- B3. Pas de table de battement de cœur, si la partie A montre des authentifications à toutes les heures : le
--     traitement des paquets en fait en continu (≈ 5 900 par jour), et chacune fait avancer le slot. Le slot n'est
--     pas borné (EDB 12) : son retard est surveillé par scripts/check-health.sh, comme les autres. Si des heures
--     restent vides, l'équipe BI proposera une table de battement de cœur (heartbeat.action.query), à créer ici.

-- B4. Snapshot initial : ≈ 3,25 M de lignes de auth_transaction (parcours de ses 12 Go, une fois) et ≈ 84 000 de
--     otp_transaction. Créneau creux convenu avec l'équipe BI ; le snapshot démarre dès la création du connecteur.

-- Retour arrière (connecteur supprimé d'abord, côté Kafka Connect) :
-- SELECT pg_drop_replication_slot('mosip_ida_cdc');
-- DROP PUBLICATION dbz_publication;   -- seulement si elle a été créée en B2 pour ce connecteur
-- REVOKE SELECT ON ida.auth_transaction, ida.otp_transaction FROM eidreporting;
