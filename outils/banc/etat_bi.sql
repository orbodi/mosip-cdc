\echo --- bi.fait_enrolement_jour (centre = code bi.zone)
select f.jour, z.code, f.type_demande, f.inscriptions, f.niu_generes, f.en_cours, f.echouees, f.rejetees, f.non_classees
from bi.fait_enrolement_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
\echo --- bi.fait_niu_jour
select f.jour, z.code, f.type_demande, f.niu_generes from bi.fait_niu_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
\echo --- bi.source_fraicheur
select source, premiere_donnee, derniere_donnee, dernier_chargement is not null as charge from bi.source_fraicheur order by ordre;
\echo --- contrôles : NIU flux = NIU cohorte ; somme des statuts
select (select sum(niu_generes) from bi.fait_niu_jour) as niu_flux, (select sum(niu_generes) from bi.fait_enrolement_jour) as niu_cohorte,
       (select sum(inscriptions) from bi.fait_enrolement_jour) as inscriptions;
