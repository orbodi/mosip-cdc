\echo === Devenir des inscriptions, national puis région R1 (Savanes)
with recursive perimetre as (select id from bi.zone where code = cast(:'zone' as text)
  union all select z.id from bi.zone z join perimetre p on z.parent_id = p.id)
select coalesce(sum(f.inscriptions),0) inscriptions, coalesce(sum(f.niu_generes),0) niu, coalesce(sum(f.en_cours),0) en_cours,
       coalesce(sum(f.echouees),0) echouees, coalesce(sum(f.rejetees),0) rejetees, coalesce(sum(f.non_classees),0) non_classees
from bi.fait_enrolement_jour f where (cast(nullif(:'zone','') as text) is null or f.centre_id in (select id from perimetre));
\set zone R1
with recursive perimetre as (select id from bi.zone where code = cast(:'zone' as text)
  union all select z.id from bi.zone z join perimetre p on z.parent_id = p.id)
select coalesce(sum(f.inscriptions),0) inscriptions, coalesce(sum(f.niu_generes),0) niu
from bi.fait_enrolement_jour f where f.centre_id in (select id from perimetre);
\echo === Territoire national : une ligne par région (requête sousZones)
with recursive enfants as (select z.id, z.code, z.nom, z.niveau, z.ordre from bi.zone z where z.parent_id is null),
descendance as (select e.id as enfant_id, e.id as zone_id from enfants e
  union all select d.enfant_id, z.id from bi.zone z join descendance d on z.parent_id = d.zone_id),
faits as (select f.centre_id, sum(f.inscriptions) inscriptions, sum(f.niu_generes) niu from bi.fait_enrolement_jour f group by 1)
select e.code, e.nom, coalesce(sum(f.inscriptions),0) inscriptions, coalesce(sum(f.niu),0) niu
from enfants e join descendance d on d.enfant_id = e.id left join faits f on f.centre_id = d.zone_id
group by e.code, e.nom, e.ordre having e.code <> 'HORS_REFERENTIEL' or coalesce(sum(f.inscriptions),0) > 0 order by e.ordre, e.nom;
\echo === Semaines : dernière donnée (pastille) puis inscriptions et NIU par lundi
select cast(derniere_donnee at time zone 'Africa/Lome' as date) as derniere from bi.source_fraicheur where source = 'enrolement';
select cast(date_trunc('week', cast(f.jour as timestamp)) as date) lundi, 'inscriptions' serie, sum(f.inscriptions) from bi.fait_enrolement_jour f group by 1 union all
select cast(date_trunc('week', cast(f.jour as timestamp)) as date), 'niu', sum(f.niu_generes) from bi.fait_niu_jour f group by 1 order by 1, 2;
\echo === Top des centres (inscriptions)
select z.code, z.nom, sum(f.inscriptions) inscriptions from bi.fait_enrolement_jour f join bi.zone z on z.id = f.centre_id
group by 1, 2 order by 3 desc, 2 limit 5;
\echo === NIU par âge, sexe et nationalité (lot 6, requêtes niuParSexeEtAge et niuParNationalite), national
select f.sexe, f.tranche_age, sum(f.niu_generes) niu_generes from bi.fait_niu_profil_jour f group by 1, 2 order by 1, 2;
select f.nationalite, sum(f.niu_generes) niu_generes from bi.fait_niu_nationalite_jour f group by 1 order by 2 desc, 1;
\echo === Droits : publisher peut écrire les faits, api_reader seulement lire
select has_table_privilege('publisher','bi.fait_enrolement_jour','INSERT') pub_ins, has_table_privilege('publisher','bi.fait_niu_jour','DELETE') pub_del,
       has_table_privilege('api_reader','bi.fait_enrolement_jour','SELECT') api_sel, has_table_privilege('api_reader','bi.fait_enrolement_jour','INSERT') api_ins,
       has_schema_privilege('api_reader','dwh','USAGE') api_dwh,
       has_table_privilege('api_reader','bi.fait_niu_nationalite_jour','SELECT') api_nat,
       has_table_privilege('publisher','bi.fait_niu_profil_jour','INSERT') pub_profil;
