-- Relevé de l'enrôlement sur mosip_regprc : COMPTAGES SEULEMENT, aucune écriture, aucun RID ni texte libre affiché.
-- Sert l'analyse docs/analyse-enrolement.md (réponses R1 à R9, R11, R12). Le NIU (uin) et le numéro d'état civil de
-- rid_uin_link ne sont jamais affichés, seulement comptés. À exécuter par le DBA, de préférence sur une réplique
-- ou hors heures de pointe (registration_transaction peut compter plusieurs dizaines de millions de lignes) :
--   psql -h <serveur MOSIP> -U <dba> -d mosip_regprc -X -A -F ';' -f sql/mosip/03_releve_enrolement_regprc.sql \
--        -o releve_regprc.txt
-- Si la transaction de génération du NIU n'est pas UIN_GENERATOR / PROCESSED (voir R6), relancer R7 avec :
--   -v trn_niu=<code> -v statut_niu=<statut>
-- Les seuls identifiants affichés sont des préfixes de RID (5 chiffres = centre, 10 = centre + machine), qui
-- désignent des centres et des postes, pas des personnes.
\set ON_ERROR_STOP on
\pset footer off
\if :{?trn_niu}
\else
\set trn_niu UIN_GENERATOR
\endif
\if :{?statut_niu}
\else
\set statut_niu PROCESSED
\endif

\qecho '##### R1. Volumes'
SELECT relname AS table_regprc, n_live_tup AS lignes_estimees,
       pg_size_pretty(pg_total_relation_size(relid)) AS taille
FROM pg_stat_user_tables
WHERE schemaname = 'regprc'
ORDER BY n_live_tup DESC;
SELECT count(*) AS registration_lignes FROM regprc.registration;

\qecho '##### R2. Statuts et types (regprc.registration)'
SELECT status_code, count(*) AS inscriptions FROM regprc.registration GROUP BY 1 ORDER BY 2 DESC;
SELECT reg_type, count(*) AS inscriptions FROM regprc.registration GROUP BY 1 ORDER BY 2 DESC;
SELECT reg_type, status_code, count(*) AS inscriptions FROM regprc.registration GROUP BY 1, 2 ORDER BY 1, 3 DESC;
\qecho '-- croisement statut du paquet x dernière transaction (règle 1 : quel statut regrouper)'
SELECT status_code, latest_trn_type_code, latest_trn_status_code, count(*) AS inscriptions
FROM regprc.registration GROUP BY 1, 2, 3 ORDER BY 4 DESC;
SELECT reg_stage_name, status_code, count(*) AS inscriptions
FROM regprc.registration GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT is_deleted, is_active, count(*) AS inscriptions FROM regprc.registration GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT coalesce(reg_process_retry_count, 0) AS retraitements, count(*) AS inscriptions
FROM regprc.registration GROUP BY 1 ORDER BY 1;

\qecho '##### R3. Dates (règle 2 : cr_dtimes ou pkt_cr_dtimes ; fuseau horaire)'
SELECT min(cr_dtimes) AS premiere_reception, max(cr_dtimes) AS derniere_reception,
       min(pkt_cr_dtimes) AS premier_paquet, max(pkt_cr_dtimes) AS dernier_paquet,
       max(upd_dtimes) AS derniere_modification,
       count(*) FILTER (WHERE pkt_cr_dtimes IS NULL) AS sans_date_paquet,
       count(*) FILTER (WHERE latest_trn_dtimes IS NULL) AS sans_date_transaction
FROM regprc.registration;
SELECT to_char(cr_dtimes, 'YYYY-MM') AS mois_reception, count(*) AS inscriptions
FROM regprc.registration GROUP BY 1 ORDER BY 1;
\qecho '-- délai de remontée : réception par MOSIP - création du paquet au centre'
SELECT CASE
         WHEN pkt_cr_dtimes IS NULL THEN '0. sans date de paquet'
         WHEN cr_dtimes < pkt_cr_dtimes THEN '1. négatif'
         WHEN cr_dtimes - pkt_cr_dtimes < interval '1 day' THEN '2. moins de 1 jour'
         WHEN cr_dtimes - pkt_cr_dtimes < interval '3 days' THEN '3. 1 à 3 jours'
         WHEN cr_dtimes - pkt_cr_dtimes < interval '7 days' THEN '4. 3 à 7 jours'
         WHEN cr_dtimes - pkt_cr_dtimes < interval '30 days' THEN '5. 7 à 30 jours'
         ELSE '6. 30 jours et plus'
       END AS delai_remontee, count(*) AS inscriptions
FROM regprc.registration GROUP BY 1 ORDER BY 1;
SELECT round(cast(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM cr_dtimes - pkt_cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_remontee_median_jours,
       round(cast(percentile_cont(0.9) WITHIN GROUP (ORDER BY extract(epoch FROM cr_dtimes - pkt_cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_remontee_p90_jours
FROM regprc.registration WHERE pkt_cr_dtimes IS NOT NULL;
\qecho '-- heures d activité : paquets créés au centre (heure locale probable) et reçus par MOSIP'
SELECT extract(hour FROM pkt_cr_dtimes) AS heure, count(*) AS paquets_crees
FROM regprc.registration GROUP BY 1 ORDER BY 1;
SELECT extract(hour FROM cr_dtimes) AS heure, count(*) AS paquets_recus
FROM regprc.registration GROUP BY 1 ORDER BY 1;

\qecho '##### R4. Préfixes du RID (centre = 5 premiers chiffres ? machine = 5 suivants ?)'
SELECT length(id) AS longueur_rid, count(*) AS inscriptions,
       count(*) FILTER (WHERE id !~ '^[0-9]+$') AS non_numeriques
FROM regprc.registration GROUP BY 1 ORDER BY 2 DESC;
SELECT count(DISTINCT left(id, 5)) AS prefixes_5, count(DISTINCT left(id, 10)) AS prefixes_10
FROM regprc.registration;
\qecho '-- liste complète des préfixes à 5 chiffres, à comparer à master.registration_center.id'
SELECT left(id, 5) AS prefixe_centre, count(*) AS inscriptions, count(DISTINCT left(id, 10)) AS machines,
       to_char(min(cr_dtimes), 'YYYY-MM-DD') AS premiere, to_char(max(cr_dtimes), 'YYYY-MM-DD') AS derniere
FROM regprc.registration GROUP BY 1 ORDER BY 1;
\qecho '-- les 14 derniers chiffres sont-ils un horodatage AAAAMMJJHHMISS proche de pkt_cr_dtimes ?'
SELECT count(*) FILTER (WHERE right(id, 14) = to_char(pkt_cr_dtimes, 'YYYYMMDDHH24MISS')) AS egal_pkt_cr_dtimes,
       count(*) FILTER (WHERE left(right(id, 14), 8) = to_char(pkt_cr_dtimes, 'YYYYMMDD')) AS meme_jour_pkt_cr_dtimes,
       count(*) AS total
FROM regprc.registration WHERE length(id) = 29;

\qecho '##### R5. Inscriptions non terminées : ancienneté de la dernière transaction, par statut et étape'
SELECT status_code, reg_stage_name,
       CASE
         WHEN latest_trn_dtimes IS NULL THEN '0. sans date'
         WHEN now() AT TIME ZONE 'UTC' - latest_trn_dtimes < interval '7 days' THEN '1. moins de 7 jours'
         WHEN now() AT TIME ZONE 'UTC' - latest_trn_dtimes < interval '30 days' THEN '2. 7 à 30 jours'
         WHEN now() AT TIME ZONE 'UTC' - latest_trn_dtimes < interval '180 days' THEN '3. 30 à 180 jours'
         ELSE '4. 180 jours et plus'
       END AS anciennete_derniere_transaction,
       count(*) AS inscriptions
FROM regprc.registration
WHERE NOT coalesce(is_deleted, false)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

\qecho '##### R6. Transactions (regprc.registration_transaction)'
SELECT trn_type_code, status_code, count(*) AS transactions, count(DISTINCT reg_id) AS inscriptions
FROM regprc.registration_transaction GROUP BY 1, 2 ORDER BY 1, 3 DESC;
SELECT trn_type_code, status_code, sub_status_code, count(*) AS transactions
FROM regprc.registration_transaction GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 200;
SELECT ref_id_type, count(*) AS transactions FROM regprc.registration_transaction GROUP BY 1 ORDER BY 2 DESC;
\qecho '-- transactions par inscription'
SELECT CASE WHEN n < 5 THEN '1. moins de 5' WHEN n < 10 THEN '2. 5 à 9' WHEN n < 20 THEN '3. 10 à 19'
            WHEN n < 50 THEN '4. 20 à 49' ELSE '5. 50 et plus' END AS transactions_par_inscription,
       count(*) AS inscriptions
FROM (SELECT reg_id, count(*) AS n FROM regprc.registration_transaction GROUP BY 1) t
GROUP BY 1 ORDER BY 1;
\qecho '-- transactions créées par mois (volume du flux à capter)'
SELECT to_char(cr_dtimes, 'YYYY-MM') AS mois, count(*) AS transactions
FROM regprc.registration_transaction GROUP BY 1 ORDER BY 1;

\qecho '##### R7. Date du NIU : transaction' :'trn_niu' '/' :'statut_niu'
WITH gen AS (
    SELECT reg_id, min(cr_dtimes) AS niu_le, count(*) AS n
    FROM regprc.registration_transaction
    WHERE trn_type_code = :'trn_niu' AND status_code = :'statut_niu'
    GROUP BY 1
)
SELECT r.reg_type, r.status_code,
       count(*) AS inscriptions,
       count(g.reg_id) AS avec_transaction_niu,
       count(*) FILTER (WHERE g.n > 1) AS plusieurs_transactions_niu
FROM regprc.registration r
LEFT JOIN gen g ON g.reg_id = r.id
GROUP BY 1, 2
ORDER BY 3 DESC;
\qecho '-- délai réception -> NIU (jours), et erreur de l estimation par latest_trn_dtimes (option a)'
WITH gen AS (
    SELECT reg_id, min(cr_dtimes) AS niu_le
    FROM regprc.registration_transaction
    WHERE trn_type_code = :'trn_niu' AND status_code = :'statut_niu'
    GROUP BY 1
)
SELECT r.reg_type,
       count(*) AS niu,
       round(cast(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM g.niu_le - r.cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_median_jours,
       round(cast(percentile_cont(0.9) WITHIN GROUP (ORDER BY extract(epoch FROM g.niu_le - r.cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_p90_jours,
       count(*) FILTER (WHERE to_char(r.latest_trn_dtimes, 'YYYYMMDD') = to_char(g.niu_le, 'YYYYMMDD'))
           AS estimation_meme_jour,
       count(*) FILTER (WHERE r.latest_trn_dtimes - g.niu_le < interval '7 days') AS estimation_moins_7_jours
FROM regprc.registration r
JOIN gen g ON g.reg_id = r.id
GROUP BY 1
ORDER BY 2 DESC;

\qecho '##### R8. Synchronisation (regprc.registration_list) : paquets synchronisés et chargés'
SELECT status_code, client_status_code, count(*) AS paquets FROM regprc.registration_list GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT reg_type, count(*) AS paquets FROM regprc.registration_list GROUP BY 1 ORDER BY 2 DESC;
SELECT count(*) AS lignes, count(DISTINCT reg_id) AS inscriptions_distinctes FROM regprc.registration_list;
SELECT count(*) AS synchronises_non_charges
FROM (SELECT DISTINCT reg_id FROM regprc.registration_list) l
WHERE NOT EXISTS (SELECT 1 FROM regprc.registration r WHERE r.id = l.reg_id);
SELECT count(*) AS charges_sans_synchronisation
FROM regprc.registration r
WHERE NOT EXISTS (SELECT 1 FROM regprc.registration_list l WHERE l.reg_id = r.id);

\qecho '##### R9. Vérification manuelle (regprc.reg_manual_verification)'
SELECT status_code, reason_code, trntyp_code, count(*) AS lignes, count(DISTINCT reg_id) AS inscriptions
FROM regprc.reg_manual_verification GROUP BY 1, 2, 3 ORDER BY 4 DESC;

\qecho '##### R11. Lien inscription -> NIU (regprc.rid_uin_link, table propre à l ANID)'
SELECT reg_type, count(*) AS liens, count(DISTINCT reg_id) AS inscriptions,
       count(uin) AS avec_niu, count(DISTINCT uin) AS niu_distincts,
       count(civil_registry_number) AS avec_numero_etat_civil,
       count(*) FILTER (WHERE entry_date IS NULL) AS sans_date,
       to_char(min(entry_date), 'YYYY-MM-DD HH24:MI') AS premiere, to_char(max(entry_date), 'YYYY-MM-DD HH24:MI') AS derniere
FROM regprc.rid_uin_link GROUP BY 1 ORDER BY 2 DESC;
SELECT to_char(entry_date, 'YYYY-MM') AS mois, count(*) AS liens FROM regprc.rid_uin_link GROUP BY 1 ORDER BY 1;
SELECT extract(hour FROM entry_date) AS heure, count(*) AS liens FROM regprc.rid_uin_link GROUP BY 1 ORDER BY 1;
\qecho '-- longueur de reg_id (varchar 100) et liens sans inscription (orphelins)'
SELECT length(reg_id) AS longueur, length(trim(reg_id)) AS longueur_sans_espaces, count(*) AS liens
FROM regprc.rid_uin_link GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT count(*) AS liens_orphelins
FROM regprc.rid_uin_link l
WHERE NOT EXISTS (SELECT 1 FROM regprc.registration r WHERE r.id = trim(l.reg_id));
\qecho '-- croisement avec registration : type et statut de l inscription, type du lien'
SELECT r.reg_type, r.status_code, l.reg_type AS type_lien, count(*) AS inscriptions
FROM regprc.registration r
LEFT JOIN regprc.rid_uin_link l ON trim(l.reg_id) = r.id
GROUP BY 1, 2, 3 ORDER BY 4 DESC;
\qecho '-- entry_date est-elle l heure de génération du NIU ? (comparaison avec la transaction' :'trn_niu' '/' :'statut_niu' ')'
WITH gen AS (
    SELECT reg_id, min(cr_dtimes) AS trn_le
    FROM regprc.registration_transaction
    WHERE trn_type_code = :'trn_niu' AND status_code = :'statut_niu'
    GROUP BY 1
)
SELECT CASE
         WHEN g.reg_id IS NULL THEN '0. sans transaction de génération'
         WHEN l.entry_date < g.trn_le - interval '1 hour' THEN '1. entry_date plus d une heure avant'
         WHEN l.entry_date <= g.trn_le + interval '1 hour' THEN '2. à une heure près'
         WHEN l.entry_date <= g.trn_le + interval '1 day' THEN '3. dans le jour qui suit'
         ELSE '4. plus d un jour après'
       END AS entry_date_vs_transaction, count(*) AS liens
FROM regprc.rid_uin_link l
LEFT JOIN gen g ON g.reg_id = trim(l.reg_id)
GROUP BY 1 ORDER BY 1;
\qecho '-- délai réception -> NIU par entry_date (jours), par type ; délais négatifs'
SELECT l.reg_type, count(*) AS liens,
       count(*) FILTER (WHERE l.entry_date < r.cr_dtimes) AS delai_negatif,
       round(cast(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM l.entry_date - r.cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_median_jours,
       round(cast(percentile_cont(0.9) WITHIN GROUP (ORDER BY extract(epoch FROM l.entry_date - r.cr_dtimes) / 86400)
                  AS numeric), 2) AS delai_p90_jours
FROM regprc.rid_uin_link l
JOIN regprc.registration r ON r.id = trim(l.reg_id)
GROUP BY 1 ORDER BY 2 DESC;
SELECT applicant_type, count(*) AS inscriptions FROM regprc.registration GROUP BY 1 ORDER BY 2 DESC;

\qecho '##### R12. Publication existante et configuration de la capture'
SELECT version();
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate FROM pg_publication;
SELECT pubname, schemaname, tablename FROM pg_publication_tables WHERE schemaname = 'regprc' ORDER BY 1, 3;
SELECT c.relname AS table_regprc, c.relreplident AS replica_identity
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'regprc'
  AND c.relname IN ('registration', 'registration_transaction', 'registration_list', 'rid_uin_link')
ORDER BY 1;
SELECT slot_name, plugin, database, active, wal_status FROM pg_replication_slots ORDER BY 1;

\qecho '##### Référentiel des types de transaction (libellés, aucune donnée personnelle)'
SELECT code, lang_code, descr, is_active FROM regprc.transaction_type ORDER BY code, lang_code;
