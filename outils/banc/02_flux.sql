-- Changements après le snapshot (op c et u), tels que les écrivent les connecteurs : upsert dans l'ODS (nouvel
-- offset), ajout dans le journal du lake. À exécuter par ods_writer.
--
--  R2  sort enfin de la vérification manuelle : NIU généré le 25/10 à 01h00 (lien), statut PROCESSED
--  L10 est reçu par MOSIP le 24/10 à 20h00 : en cours (réception du paquet)
--  R5  reste échoué (mise à jour sans changement de devenir)
--  R1  : entry_date du lien modifiée après coup (alerte du test assert_rid_uin_link_date_modifiee)
--  L13 nouvelle synchronisation, pas encore reçue
--  Enrichissement (lot 6) : R2 Homme, BENIN (absent de la liste : valeur gardée telle quelle), né en 2010 sans mois
--  (16 ans au NIU : 15-18) ; R7 (sans NIU) genre « Inconnu » : alerte assert_enrolement_genres_inconnus, aucun effet
--  sur les faits ; R1 répond à nouveau, à l'identique
insert into ods.regprc_registration
 (id, reg_type, status_code, latest_trn_type_code, latest_trn_status_code, latest_trn_dtimes, reg_stage_name,
  cr_dtimes, upd_dtimes, __deleted, __op, __source_ts_ms, __kafka_offset, status_comment) values
 ('10001000010000220260704080000','NEW','PROCESSED','UIN_GENERATOR','PROCESSED','2026-10-25 01:01','UinGeneratorStage','2026-07-04 09:00','2026-10-25 01:01','false','u',1792890000000,8,'UIN Generated Successfully'),
 ('10001000020001020261023170000','NEW','PROCESSING','PACKET_RECEIVER','SUCCESS','2026-10-24 20:00','PacketReceiverStage','2026-10-24 20:00','2026-10-24 20:00','false','c',1792890000000,9,'Packet is Uploaded to Landing Zone'),
 ('88888000010000520261005100000','NEW','FAILED','OSI_VALIDATE','FAILED','2026-10-05 12:00','OSIValidatorStage','2026-10-05 10:20','2026-10-24 21:00','false','u',1792890000000,10,'Biometric data - Iris did not match')
on conflict (id) do update set reg_type = excluded.reg_type, status_code = excluded.status_code,
  latest_trn_type_code = excluded.latest_trn_type_code, latest_trn_status_code = excluded.latest_trn_status_code,
  latest_trn_dtimes = excluded.latest_trn_dtimes, reg_stage_name = excluded.reg_stage_name,
  cr_dtimes = excluded.cr_dtimes, upd_dtimes = excluded.upd_dtimes, __op = excluded.__op,
  __source_ts_ms = excluded.__source_ts_ms, __kafka_offset = excluded.__kafka_offset,
  status_comment = excluded.status_comment;

insert into ods.regprc_rid_uin_link
 (id, reg_id, reg_type, entry_date, __deleted, __op, __source_ts_ms, __kafka_offset) values
 (1002,'10001000010000220260704080000','NEW','2026-10-25 01:00','false','c',1792890000000,2),
 (1001,'10001000010000120261001080000','NEW','2026-10-01 18:30','false','u',1792890000000,3)
on conflict (id) do update set entry_date = excluded.entry_date, __op = excluded.__op,
  __source_ts_ms = excluded.__source_ts_ms, __kafka_offset = excluded.__kafka_offset;

insert into lake.mosip_regprc_rid_uin_link
 (__connect_topic, __connect_partition, __connect_offset, id, reg_id, reg_type, entry_date, __deleted, __op, __lsn,
  __source_ts_ms) values
 ('mosip.regprc.rid_uin_link',0,2,1002,'10001000010000220260704080000','NEW','2026-10-25 01:00','false','c',200,1792890000000),
 ('mosip.regprc.rid_uin_link',0,3,1001,'10001000010000120261001080000','NEW','2026-10-01 18:30','false','u',201,1792890000000);

insert into ods.regprc_registration_list
 (id, reg_id, reg_type, client_status_code, cr_dtimes, upd_dtimes, __deleted, __op, __source_ts_ms, __kafka_offset) values
 ('S13','20001000020001320261024230000','NEW','APPROVED','2026-10-25 00:10','2026-10-25 00:10','false','c',1792890000000,11);

insert into lake.mosip_regprc_enrichissement
 (__connect_topic, __connect_partition, __connect_offset, rid, genre, nationalite, annee_naissance, mois_naissance,
  api_statut, enrichi_le) values
 ('mosip.regprc.enrichissement',0,1,'10001000010000220260704080000','Homme','BENIN',2010,null,200,now() - interval '1 hour'),
 ('mosip.regprc.enrichissement',0,2,'20001000010000720261024070000','Inconnu','TOGO',1980,1,200,now() - interval '1 hour'),
 ('mosip.regprc.enrichissement',0,3,'10001000010000120261001080000','Femme','TOGO',1990,5,200,now() - interval '1 hour');
insert into ods.regprc_enrichissement values
 ('10001000010000220260704080000','Homme','BENIN',2010,null,200,now() - interval '1 hour'),
 ('20001000010000720261024070000','Inconnu','TOGO',1980,1,200,now() - interval '1 hour'),
 ('10001000010000120261001080000','Femme','TOGO',1990,5,200,now() - interval '1 hour')
on conflict (rid) do update set genre = excluded.genre, nationalite = excluded.nationalite,
  annee_naissance = excluded.annee_naissance, mois_naissance = excluded.mois_naissance,
  api_statut = excluded.api_statut, enrichi_le = excluded.enrichi_le;

-- Impression des cartes (lot 8) : changements après le snapshot.
--  K2  remise en ligne le 26/10 (NIU de R4 le 06/10 : 20 jours)
--  C6  envoyée le 25/10, carte K6 expédiée le 27/10
--  C7  nouvelle commande pour R2 (NIU du 25/10), en attente
--  C3  annulée avec un motif absent du catalogue (alerte : NON_REPERTORIE)
--  C1  le NIU de R1 change d'heure (lien modifié) : la commande est recalculée, même délai (18 jours)
insert into ods.regprc_printing_orders
 (id, rid, request_id, prc_status, entry_date, issuing_date, __deleted, __op, __source_ts_ms, __kafka_offset) values
 (6,'10001000099999620261009080000','Q6','OK','2026-10-09 13:00','2026-10-25 08:00','false','u',1792890000000,6),
 (7,'10001000010000220260704080000','Q7','NEW','2026-10-26 09:00',null,'false','c',1792890000000,7)
on conflict (id) do update set prc_status = excluded.prc_status, entry_date = excluded.entry_date,
  issuing_date = excluded.issuing_date, __op = excluded.__op, __source_ts_ms = excluded.__source_ts_ms,
  __kafka_offset = excluded.__kafka_offset;

insert into ods.regprc_printing_shipped_cards
 (id, request_id, entry_date, delivery_status, delivery_mode, delivery_date, __deleted, __op, __source_ts_ms,
  __kafka_offset) values
 (12,'Q2','2026-10-10 10:00','DELIVERED','ONLINE','2026-10-26 15:00','false','u',1792890000000,4),
 (16,'Q6','2026-10-27 10:00','NOT_DELIVERED',null,null,'false','c',1792890000000,5)
on conflict (id) do update set delivery_status = excluded.delivery_status, delivery_mode = excluded.delivery_mode,
  delivery_date = excluded.delivery_date, __op = excluded.__op, __source_ts_ms = excluded.__source_ts_ms,
  __kafka_offset = excluded.__kafka_offset;

insert into lake.mosip_regprc_printing_orders_details
 (__connect_topic, __connect_partition, __connect_offset, id, request_id, status_code, reason_code, sub_status_code,
  cr_dtimes, __deleted, __op, __lsn, __source_ts_ms) values
 ('mosip.regprc.printing_orders_details',0,2,103,'Q2','CARD-DELIVERED',null,null,'2026-10-26 15:00','false','c',400,1792890000000),
 ('mosip.regprc.printing_orders_details',0,3,104,'Q3','NEW-PRINT-CANCELED','CANCEL_AUTRE','TERMINATED','2026-10-27 09:00','false','c',401,1792890000000);
