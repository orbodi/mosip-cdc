-- Snapshot initial (op r), tel que l'écrivent les connecteurs ods-regprc-* et lake-regprc-rid-uin-link.
-- À exécuter par ods_writer (le banc lui donne aussi le droit d'écrire dans le journal du lake).
-- RID fictifs de 29 chiffres : 5 chiffres de centre, 5 de poste, 5 de séquence, 14 d'horodatage d'enrôlement.
-- 99999 et 88888 : centres absents du référentiel.
--
-- status_comment : messages réels de MOSIP (relevé R13) ; R7 porte un message absent du catalogue des motifs (alerte).
--  R1  10001  NIU (lien), synchronisé deux fois
--  R2  10001  en cours, vérification manuelle, dernière transaction le 05/07/2026 : bloqué
--  R3  10002  rejeté à VALIDATE_PACKET, synchronisation REJECTED : refus au poste
--  R4  99999  NIU (lien), centre non référencé
--  R5  88888  échoué à OSI_VALIDATE
--  R6  10002  statut inconnu RESUMABLE : non classé ; horodatage du RID invalide
--  R7  20001  LOST, statut ERROR (en cours, récent)
--  R8  20001  rejeté à DEMOGRAPHIC_VERIFICATION
--  L10 10001  synchronisé le 23/10, pas encore reçu (en transit)
--  L11 10002  synchronisé le 01/09, jamais reçu (perdu)
--
-- Enrichissement (ID Repository, lot 6), tel que l'écrivent lake-regprc-enrichissement et ods-regprc-enrichissement :
--  R1  Femme, TOGO (code de la liste « nationality », libellé « Togo »), née en mai 1990 : 36 ans au NIU (36-45)
--  R4  pas encore enrichi : sexe I, âge inconnu, « Non renseignée »
insert into ods.regprc_registration
 (id, reg_type, status_code, latest_trn_type_code, latest_trn_status_code, latest_trn_dtimes, reg_stage_name,
  cr_dtimes, upd_dtimes, __deleted, __op, __source_ts_ms, __kafka_offset, status_comment) values
 ('10001000010000120261001080000','NEW','PROCESSED','UIN_GENERATOR','PROCESSED','2026-10-01 18:25','UinGeneratorStage','2026-10-01 10:00','2026-10-01 18:25','false','r',1792900000000,0,'UIN Generated Successfully'),
 ('10001000010000220260704080000','NEW','PROCESSING','MANUAL_VERIFICATION','SUCCESS','2026-07-05 03:10','ManualVerificationStage','2026-07-04 09:00','2026-07-05 03:10','false','r',1792900000000,1,'Manual verification Sent to queue'),
 ('10002000010000320261002090000','UPDATE','REJECTED','VALIDATE_PACKET','FAILED','2026-10-02 09:40','PacketValidatorStage','2026-10-02 09:35','2026-10-02 09:40','false','r',1792900000000,2,'Rejected by Supervisor'),
 ('99999000010000420261005080000','NEW','PROCESSED','PRINT_SERVICE','SUCCESS','2026-10-06 12:00','PrintingStage','2026-10-05 08:30','2026-10-06 12:00','false','r',1792900000000,3,'Printing sent'),
 ('88888000010000520261005100000','NEW','FAILED','OSI_VALIDATE','FAILED','2026-10-05 12:00','OSIValidatorStage','2026-10-05 10:20','2026-10-05 12:00','false','r',1792900000000,4,'Biometric data - Iris did not match'),
 ('10002000010000699999999999999','NEW','RESUMABLE','BIOGRAPHIC_VERIFICATION','REPROCESS','2026-10-06 09:00','BioDedupeStage','2026-10-06 08:00','2026-10-06 09:00','false','r',1792900000000,5,null),
 ('20001000010000720261024070000','LOST','ERROR','UIN_GENERATOR','REPROCESS','2026-10-24 09:00','UinGeneratorStage','2026-10-24 08:00','2026-10-24 09:00','false','r',1792900000000,6,'Packet queued for re-sync 12345678'),
 ('20001000010000820261008080000','NEW','REJECTED','DEMOGRAPHIC_VERIFICATION','FAILED','2026-10-09 15:00','DemoDedupeStage','2026-10-08 08:10','2026-10-09 15:00','false','r',1792900000000,7,'Biometric Duplicate was Found in ABIS');

insert into ods.regprc_registration_list
 (id, reg_id, reg_type, client_status_code, cr_dtimes, upd_dtimes, __deleted, __op, __source_ts_ms, __kafka_offset) values
 ('S01a','10001000010000120261001080000','NEW','APPROVED','2026-10-01 09:50','2026-10-01 09:50','false','r',1792900000000,0),
 ('S01b','10001000010000120261001080000','NEW','APPROVED','2026-10-01 09:55','2026-10-01 09:55','false','r',1792900000000,1),
 ('S02','10001000010000220260704080000','NEW','APPROVED','2026-07-04 08:40','2026-07-04 08:40','false','r',1792900000000,2),
 ('S03','10002000010000320261002090000','UPDATE','REJECTED','2026-10-02 09:30','2026-10-02 09:30','false','r',1792900000000,3),
 ('S04','99999000010000420261005080000','NEW','APPROVED','2026-10-05 08:20','2026-10-05 08:20','false','r',1792900000000,4),
 ('S05','88888000010000520261005100000','NEW','APPROVED','2026-10-05 10:10','2026-10-05 10:10','false','r',1792900000000,5),
 ('S06','10002000010000699999999999999','NEW','APPROVED','2026-10-06 07:50','2026-10-06 07:50','false','r',1792900000000,6),
 ('S07','20001000010000720261024070000','LOST','APPROVED','2026-10-24 07:50','2026-10-24 07:50','false','r',1792900000000,7),
 ('S08','20001000010000820261008080000','NEW','APPROVED','2026-10-08 08:00','2026-10-08 08:00','false','r',1792900000000,8),
 ('S10','10001000020001020261023170000','NEW','APPROVED','2026-10-23 17:40','2026-10-23 17:40','false','r',1792900000000,9),
 ('S11','10002000020001120260901100000','NEW','APPROVED','2026-09-01 10:30','2026-09-01 10:30','false','r',1792900000000,10);

insert into ods.regprc_rid_uin_link
 (id, reg_id, reg_type, entry_date, __deleted, __op, __source_ts_ms, __kafka_offset) values
 (1001,'10001000010000120261001080000','NEW','2026-10-01 18:24','false','r',1792900000000,0),
 (1004,'99999000010000420261005080000','NEW','2026-10-06 11:05','false','r',1792900000000,1);

insert into lake.mosip_regprc_rid_uin_link
 (__connect_topic, __connect_partition, __connect_offset, id, reg_id, reg_type, entry_date, __deleted, __op, __lsn,
  __source_ts_ms) values
 ('mosip.regprc.rid_uin_link',0,0,1001,'10001000010000120261001080000','NEW','2026-10-01 18:24','false','r',100,1792900000000),
 ('mosip.regprc.rid_uin_link',0,1,1004,'99999000010000420261005080000','NEW','2026-10-06 11:05','false','r',100,1792900000000);

insert into lake.mosip_regprc_enrichissement
 (__connect_topic, __connect_partition, __connect_offset, rid, genre, nationalite, annee_naissance, mois_naissance,
  api_statut, enrichi_le) values
 ('mosip.regprc.enrichissement',0,0,'10001000010000120261001080000','Femme','TOGO',1990,5,200,'2026-10-01 19:00');
insert into ods.regprc_enrichissement values
 ('10001000010000120261001080000','Femme','TOGO',1990,5,200,'2026-10-01 19:00');

-- Liste MOSIP « nationality » (master.dynamic_field) : seul TOGO y figure
insert into lake.mosip_master_dynamic_field
 (__connect_topic, __connect_partition, __connect_offset, id, name, description, data_type, value_json, lang_code,
  is_active, is_deleted, cr_dtimes, upd_dtimes, __deleted, __op, __lsn, __source_ts_ms) values
 ('mosip.master.dynamic_field',0,0,'DF1','nationality','Nationalité','string',
  '[{"code":"TOGO","value":"Togo","langCode":"fra","active":true}]','fra',true,false,now(),null,'false','r',1,0);

-- Impression des cartes (lot 8), tel que l'écrivent ods-regprc-printing-orders, ods-regprc-printing-shipped-cards et
-- lake-regprc-printing-orders-details (snapshot : historique réduit aux annulations et aux erreurs d'envoi).
--  C1  R1     10001  OK, carte K1 expédiée le 06/10, remise hors ligne le 20/10 (NIU le 01/10 : 18 jours)
--  C2  R4     99999  OK, carte K2 expédiée le 10/10, pas encore remise ; centre non référencé
--  C3  10002         NEW, carte K3 expédiée le 15/07 quand même, NOT_DELIVERED SUPPORT avec une date de remise
--                    (deux anomalies du relevé)
--  C4  20001         KO (rejetée)
--  C5  20001         OK, annulée le 06/10 (CANCEL_PHOTO), sans carte
--  C6  10001         NEW (en attente)
--  K9                carte dont la commande est absente (alerte assert_impression_cartes_sans_commande)
insert into ods.regprc_printing_orders
 (id, rid, request_id, prc_status, entry_date, issuing_date, __deleted, __op, __source_ts_ms, __kafka_offset) values
 (1,'10001000010000120261001080000','Q1','OK','2026-10-02 08:00','2026-10-02 16:30','false','r',1792900000000,0),
 (2,'99999000010000420261005080000','Q2','OK','2026-10-07 09:00','2026-10-07 17:00','false','r',1792900000000,1),
 (3,'10002000099999920260709080000','Q3','NEW','2026-07-10 10:00',null,'false','r',1792900000000,2),
 (4,'20001000099999820261004080000','Q4','KO','2026-10-04 11:00',null,'false','r',1792900000000,3),
 (5,'20001000099999720261005080000','Q5','OK','2026-10-05 12:00','2026-10-05 20:00','false','r',1792900000000,4),
 (6,'10001000099999620261009080000','Q6','NEW','2026-10-09 13:00',null,'false','r',1792900000000,5);

insert into ods.regprc_printing_shipped_cards
 (id, request_id, entry_date, delivery_status, delivery_mode, delivery_date, __deleted, __op, __source_ts_ms,
  __kafka_offset) values
 (11,'Q1','2026-10-06 10:00','DELIVERED','OFFLINE','2026-10-20 11:00','false','r',1792900000000,0),
 (12,'Q2','2026-10-10 10:00','NOT_DELIVERED',null,null,'false','r',1792900000000,1),
 (13,'Q3','2026-07-15 10:00','NOT_DELIVERED','SUPPORT','2026-07-20 10:00','false','r',1792900000000,2),
 (19,'Q-ORPHELINE','2026-10-11 10:00','NOT_DELIVERED',null,null,'false','r',1792900000000,3);

insert into lake.mosip_regprc_printing_orders_details
 (__connect_topic, __connect_partition, __connect_offset, id, request_id, status_code, reason_code, sub_status_code,
  cr_dtimes, __deleted, __op, __lsn, __source_ts_ms) values
 ('mosip.regprc.printing_orders_details',0,0,101,'Q1','PRINT-REQUEST-ERR','CORE-PRINTING-IDPS-1',null,'2026-10-02 12:00','false','r',300,1792900000000),
 ('mosip.regprc.printing_orders_details',0,1,102,'Q5','NEW-PRINT-CANCELED','CANCEL_PHOTO','TERMINATED','2026-10-06 09:00','false','r',300,1792900000000);
