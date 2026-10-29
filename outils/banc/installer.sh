#!/usr/bin/env bash
# Banc de test de la chaîne enrôlement : crée une base mosip_bi JETABLE sur un PostgreSQL local (jamais celui du
# serveur), avec les rôles de la BD traitement, le contrat bi (migrations Flyway du backend appliquées par
# bi_owner), le lake et l'ODS des pré-inscriptions et un petit référentiel MOSIP (2 régions, 3 centres).
#
#   PGHOST=/tmp PGUSER=postgres outils/banc/installer.sh
#
# Variables : PGHOST, PGPORT, PGUSER (superutilisateur du PostgreSQL de test), REPORTING (dépôt mosip-bi-reporting,
# par défaut à côté de mosip-cdc). Les rôles sont créés sans mot de passe : authentification « trust » attendue.
set -euo pipefail
CDC=$(cd "$(dirname "$0")/../.." && pwd)
REPORTING=${REPORTING:-$CDC/../mosip-bi-reporting}
SU=${PGUSER:-postgres}
case "${PGHOST:-localhost}" in
  172.16.*|*mosip*) echo "Refusé : le banc ne tourne que sur un PostgreSQL local jetable." >&2; exit 1 ;;
esac
P="psql -U $SU -v ON_ERROR_STOP=1 -q"
en() { local r=$1; shift; psql -U "$r" -d mosip_bi -v ON_ERROR_STOP=1 -q "$@"; }

$P -d postgres -c "drop database if exists mosip_bi" -c "create database mosip_bi"
for r in dbt_runner publisher publisher_ro ingest_writer ods_writer api_reader bi_owner spark_reader; do
  $P -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = '$r') then
                       create role $r login; end if; end \$\$"
done
$P -d postgres -c "grant publisher_ro to publisher" 2>/dev/null || true

# Schémas de la BD traitement (scripts 01, 02 et 11 absents du dépôt : droits supposés équivalents)
$P -d mosip_bi -c "create schema lake authorization ingest_writer; create schema ods authorization ods_writer;
                   create schema ref authorization publisher; create schema ind authorization publisher;
                   create schema bi authorization bi_owner;
                   grant create on database mosip_bi to dbt_runner, bi_owner;
                   grant usage on schema lake to dbt_runner; grant usage on schema ods to publisher, spark_reader"

# Prérequis du propriétaire (pgcrypto, usage du schéma ods), comme sur le serveur
$P -d mosip_bi -f "$CDC/sql/traitement/17_prerequis_proprietaire.sql" >/dev/null

# Contrat bi : migrations du backend, comme Flyway au démarrage de l'API
# Dans l'ordre des versions, comme Flyway (V10 après V9, et non après V1 comme le tri alphabétique)
while read -r v; do en bi_owner -f "$v"; done < <(ls "$REPORTING"/backend/src/main/resources/db/migration/V*.sql | sort -V)
en bi_owner -f "$CDC/sql/traitement/09_droits_bi.sql" -f "$CDC/sql/traitement/12_droits_bi_zone.sql" \
  -f "$CDC/sql/traitement/13_droits_bi_profil_preinscriptions.sql" -f "$CDC/sql/traitement/16_droits_bi_enrolement.sql"

# Lake existant (créé par les connecteurs sur le serveur) et référentiel de test
en ingest_writer <<'SQL'
create table lake.mosip_prereg_applicant_demographic (__connect_topic text, __connect_partition int,
  __connect_offset bigint, prereg_id text, status_code text, lang_code text, cr_dtimes timestamp, upd_dtimes timestamp,
  __deleted text, __op text, __lsn bigint, __source_ts_ms bigint);
create table lake.mosip_master_location (__connect_topic text, __connect_partition int, __connect_offset bigint,
  code text, lang_code text, name text, hierarchy_level smallint, hierarchy_level_name text, parent_loc_code text,
  is_active boolean, is_deleted boolean, cr_dtimes timestamp, upd_dtimes timestamp, __deleted text, __op text,
  __lsn bigint, __source_ts_ms bigint);
create table lake.mosip_master_registration_center (__connect_topic text, __connect_partition int,
  __connect_offset bigint, id text, lang_code text, name text, cntrtyp_code text, location_code text, zone_code text,
  latitude text, longitude text, is_active boolean, is_deleted boolean, cr_dtimes timestamp, upd_dtimes timestamp,
  __deleted text, __op text, __lsn bigint, __source_ts_ms bigint);
create table lake.mosip_master_dynamic_field (__connect_topic text, __connect_partition int, __connect_offset bigint,
  id text, name text, description text, data_type text, value_json text, lang_code text, is_active boolean,
  is_deleted boolean, cr_dtimes timestamp, upd_dtimes timestamp, __deleted text, __op text, __lsn bigint,
  __source_ts_ms bigint);
grant select on all tables in schema lake to dbt_runner;
insert into lake.mosip_master_location values
 ('t',0,0,'TGO','fra','Togo',0,'Pays',null,true,false,now(),null,'false','r',1,0),
 ('t',0,1,'R1','fra','SAVANES',1,'Région','TGO',true,false,now(),null,'false','r',1,0),
 ('t',0,2,'R2','fra','KARA',1,'Région','TGO',true,false,now(),null,'false','r',1,0),
 ('t',0,3,'P11','fra','TONE',2,'Préfecture','R1',true,false,now(),null,'false','r',1,0),
 ('t',0,4,'P21','fra','KOZAH',2,'Préfecture','R2',true,false,now(),null,'false','r',1,0);
insert into lake.mosip_master_registration_center values
 ('t',0,0,'10001','fra','EPP Dapaong','REG','P11',null,null,null,true,false,now(),null,'false','r',1,0),
 ('t',0,1,'10002','fra','EPP Nano','REG','P11',null,null,null,true,false,now(),null,'false','r',1,0),
 ('t',0,2,'20001','fra','EPP Kara','REG','P21',null,null,null,true,false,now(),null,'false','r',1,0);
-- Une pré-inscription : sans elle, le test not_null de fraicheur_preinscription échoue
insert into lake.mosip_prereg_applicant_demographic values ('mosip.prereg.applicant_demographic',0,0,'P0001',
  'Booked','fra','2026-10-01 10:00','2026-10-02 10:00','false','r',1,1792900000000);
SQL
en ingest_writer -f "$CDC/sql/traitement/04_enrichissement.sql" -f "$CDC/sql/traitement/15_lake_regprc.sql" \
  -f "$CDC/sql/traitement/19_lake_regprc_enrichissement.sql"
# Les fichiers de données du banc (01_snapshot.sql, 02_flux.sql) jouent les connecteurs : ods_writer écrit aussi le
# journal du lake, ce que fait ingest_writer sur le serveur.
en ingest_writer -c "grant usage on schema lake to ods_writer; grant insert on lake.mosip_regprc_rid_uin_link,
                     lake.mosip_regprc_enrichissement, lake.mosip_master_dynamic_field to ods_writer"
en ingest_writer -c "grant select on lake.mosip_prereg_enrichissement to dbt_runner"
en ods_writer -c "create table ods.applicant_demographic (prereg_id text primary key, status_code text,
                  cr_dtimes timestamp, upd_dtimes timestamp);
                  grant select on ods.applicant_demographic to publisher"
en ods_writer -f "$CDC/sql/traitement/14_ods_regprc.sql" -f "$CDC/sql/traitement/20_ods_regprc_enrichissement.sql"

# Premier passage dbt (crée dwh et dm_*), droits supposés existants sur dwh et dm_preinscription, tables ref / ind
"$(dirname "$0")/passage.sh" --sans-publication || true
en dbt_runner -c "grant usage on schema dwh, dm_preinscription to publisher_ro;
                  grant select on all tables in schema dwh to publisher_ro"
en publisher -f "$CDC/sql/traitement/03_publication.sql"
echo "banc installé : base mosip_bi prête (ODS de l'enrôlement vide)"
