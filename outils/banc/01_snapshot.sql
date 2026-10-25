-- Snapshot initial (op r), tel que l'écrivent les connecteurs ods-regprc-* et lake-regprc-rid-uin-link.
-- À exécuter par ods_writer (le banc lui donne aussi le droit d'écrire dans le journal du lake).
-- RID fictifs de 29 chiffres : 5 chiffres de centre, 5 de poste, 5 de séquence, 14 d'horodatage d'enrôlement.
-- 99999 et 88888 : centres absents du référentiel.
--
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
insert into ods.regprc_registration
 (id, reg_type, status_code, latest_trn_type_code, latest_trn_status_code, latest_trn_dtimes, reg_stage_name,
  cr_dtimes, upd_dtimes, __deleted, __op, __source_ts_ms, __kafka_offset) values
 ('10001000010000120261001080000','NEW','PROCESSED','UIN_GENERATOR','PROCESSED','2026-10-01 18:25','UinGeneratorStage','2026-10-01 10:00','2026-10-01 18:25','false','r',1792900000000,0),
 ('10001000010000220260704080000','NEW','PROCESSING','MANUAL_VERIFICATION','SUCCESS','2026-07-05 03:10','ManualVerificationStage','2026-07-04 09:00','2026-07-05 03:10','false','r',1792900000000,1),
 ('10002000010000320261002090000','UPDATE','REJECTED','VALIDATE_PACKET','FAILED','2026-10-02 09:40','PacketValidatorStage','2026-10-02 09:35','2026-10-02 09:40','false','r',1792900000000,2),
 ('99999000010000420261005080000','NEW','PROCESSED','PRINT_SERVICE','SUCCESS','2026-10-06 12:00','PrintingStage','2026-10-05 08:30','2026-10-06 12:00','false','r',1792900000000,3),
 ('88888000010000520261005100000','NEW','FAILED','OSI_VALIDATE','FAILED','2026-10-05 12:00','OSIValidatorStage','2026-10-05 10:20','2026-10-05 12:00','false','r',1792900000000,4),
 ('10002000010000699999999999999','NEW','RESUMABLE','BIOGRAPHIC_VERIFICATION','REPROCESS','2026-10-06 09:00','BioDedupeStage','2026-10-06 08:00','2026-10-06 09:00','false','r',1792900000000,5),
 ('20001000010000720261024070000','LOST','ERROR','UIN_GENERATOR','IN_PROGRESS','2026-10-24 09:00','UinGeneratorStage','2026-10-24 08:00','2026-10-24 09:00','false','r',1792900000000,6),
 ('20001000010000820261008080000','NEW','REJECTED','DEMOGRAPHIC_VERIFICATION','FAILED','2026-10-09 15:00','DemoDedupeStage','2026-10-08 08:10','2026-10-09 15:00','false','r',1792900000000,7);

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
