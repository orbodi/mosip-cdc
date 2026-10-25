-- Prérequis sur mosip_regprc pour le connecteur Debezium de l'enrôlement (mosip-regprc-cdc).
-- À exécuter par un administrateur de la base MOSIP, connecté à mosip_regprc.
-- Partie A : contrôles en lecture seule, sans effet. Partie B : commandes à exécuter UNE fois, après relecture.
--
-- Trois tables sont capturées, et seulement les colonnes sans donnée d'identité ni texte libre
-- (docs/conception-enrolement.md § 2) :
--   regprc.registration      : id (RID), reg_type, status_code, latest_trn_type_code, latest_trn_status_code,
--                              latest_trn_dtimes, reg_stage_name, cr_dtimes, upd_dtimes ;
--   regprc.rid_uin_link      : id, reg_id (RID), reg_type, entry_date ;
--   regprc.registration_list : id, reg_id (RID), reg_type, client_status_code, cr_dtimes, upd_dtimes.
-- Jamais lues : uin et civil_registry_number (rid_uin_link) ; status_comment, cr_by, upd_by (registration) ; noms,
-- téléphones, adresses électroniques et autres colonnes de registration_list.
-- registration_transaction (phase 3) n'est PAS capturée ici : elle aura son propre réglage, sans snapshot.

-- =====================================================================================================
-- A. Contrôles (lecture seule)
-- =====================================================================================================
SHOW wal_level;                       -- attendu : logical
SHOW max_replication_slots;           -- au moins un slot libre de plus que les slots existants
SHOW max_wal_senders;                 -- idem
SHOW max_slot_wal_keep_size;          -- -1 = illimité : borner (voir B3)
SELECT version();                     -- PostgreSQL 15 et plus : listes de colonnes possibles dans la publication (B2)

-- Colonnes capturées présentes, avec leur type
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'regprc'
  AND table_name IN ('registration', 'rid_uin_link', 'registration_list')
  AND column_name IN ('id', 'reg_id', 'reg_type', 'status_code', 'latest_trn_type_code', 'latest_trn_status_code',
                      'latest_trn_dtimes', 'reg_stage_name', 'cr_dtimes', 'upd_dtimes', 'entry_date',
                      'client_status_code')
ORDER BY table_name, column_name;

-- Replica identity : DEFAULT (d) suffit, chaque table a une clé primaire
SELECT c.relname, c.relreplident,
       (SELECT string_agg(a.attname, ', ')
        FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
        WHERE i.indrelid = c.oid AND i.indisprimary) AS cle_primaire
FROM pg_class c
WHERE c.oid IN ('regprc.registration'::regclass, 'regprc.rid_uin_link'::regclass,
                'regprc.registration_list'::regclass);

-- Les trois tables doivent figurer dans dbz_publication. Le \d du 24/10/2026 n'affichait pas de ligne
-- « Publications » pour registration (point R12) : à vérifier ici.
SELECT pubname, schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'dbz_publication' AND schemaname = 'regprc'
ORDER BY tablename;

-- Slots existants et leur retard (Mo)
SELECT slot_name, plugin, database, active, wal_status,
       (pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) / 1048576)::int AS retard_mo
FROM pg_replication_slots;

-- =====================================================================================================
-- B. Commandes (une fois)
-- =====================================================================================================
-- B1. Lecture limitée aux colonnes capturées (le snapshot initial ne lit que celles-ci).
--     eidreporting a déjà l'attribut REPLICATION (connecteurs mosip-prereg-cdc et mosip-master-cdc).
GRANT CONNECT ON DATABASE mosip_regprc TO eidreporting;
GRANT USAGE ON SCHEMA regprc TO eidreporting;
GRANT SELECT (id, reg_type, status_code, latest_trn_type_code, latest_trn_status_code, latest_trn_dtimes,
              reg_stage_name, cr_dtimes, upd_dtimes)
    ON regprc.registration TO eidreporting;
GRANT SELECT (id, reg_id, reg_type, entry_date)
    ON regprc.rid_uin_link TO eidreporting;
GRANT SELECT (id, reg_id, reg_type, client_status_code, cr_dtimes, upd_dtimes)
    ON regprc.registration_list TO eidreporting;
-- Si le snapshot échoue sur un refus de lecture (« permission denied for table … »), la version de Debezium lit
-- toutes les colonnes. Ne PAS accorder la table entière sur rid_uin_link (uin, civil_registry_number) : prévenir
-- l'équipe BI, qui fixera snapshot.select.statement.overrides pour lire les seules colonnes autorisées.

-- B2. Publication : dbz_publication existe déjà ; le connecteur l'utilise avec son propre slot (mosip_regprc_cdc).
--     Si une des trois tables manque au contrôle de la partie A :
-- ALTER PUBLICATION dbz_publication ADD TABLE regprc.registration;
--     La publication transmet au slot toutes les colonnes ; Debezium ne garde que column.include.list, donc uin
--     n'entre jamais dans Kafka. Plus sûr à partir de PostgreSQL 15 (selon la version d'EDB) : une liste de colonnes
--     dans la publication. À décider avec le propriétaire de dbz_publication, qui sert peut-être à d'autres.

-- B3. Recommandé (postgresql.conf, puis rechargement), si ce n'est pas déjà fait pour les autres slots : un slot
--     arrêté ne doit pas remplir le disque de MOSIP.
--     max_slot_wal_keep_size = '20GB'

-- B4. Pas de table de battement de cœur : registration change à chaque étape du traitement (≈ 610 000 mises à jour
--     par jour), le slot avance seul. À revoir si l'enrôlement s'arrête plusieurs jours.

-- B5. Snapshot initial : ≈ 19 M de lignes lues (6,4 M registration, 6,0 M rid_uin_link, 6,4 M registration_list).
--     Choisir un créneau creux avec l'équipe BI ; le snapshot démarre dès la création du connecteur.

-- Retour arrière (connecteur supprimé d'abord, côté Kafka Connect) :
-- SELECT pg_drop_replication_slot('mosip_regprc_cdc');
