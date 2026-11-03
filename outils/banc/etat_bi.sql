\echo --- bi.fait_enrolement_jour (centre = code bi.zone)
select f.jour, z.code, f.type_demande, f.inscriptions, f.niu_generes, f.en_cours, f.echouees, f.rejetees, f.non_classees,
       f.en_reprocessing
from bi.fait_enrolement_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
\echo --- bi.fait_niu_jour
select f.jour, z.code, f.type_demande, f.niu_generes from bi.fait_niu_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
\echo --- bi.fait_niu_profil_jour (lot 6 : région du centre, sexe, tranche d’âge)
select f.jour, z.code, f.sexe, f.tranche_age, f.niu_generes from bi.fait_niu_profil_jour f join bi.zone z on z.id = f.zone_id order by 1, 2, 3;
\echo --- bi.fait_niu_nationalite_jour
select f.jour, z.code, f.nationalite, f.niu_generes from bi.fait_niu_nationalite_jour f join bi.zone z on z.id = f.zone_id order by 1, 2, 3;
\echo --- bi.source_fraicheur
select source, premiere_donnee, derniere_donnee, dernier_chargement is not null as charge from bi.source_fraicheur order by ordre;
\echo --- contrôles : NIU flux = NIU cohorte ; somme des statuts
select (select sum(niu_generes) from bi.fait_niu_jour) as niu_flux, (select sum(niu_generes) from bi.fait_enrolement_jour) as niu_cohorte,
       (select sum(niu_generes) from bi.fait_niu_profil_jour) as niu_profil, (select sum(niu_generes) from bi.fait_niu_nationalite_jour) as niu_nationalite,
       (select sum(inscriptions) from bi.fait_enrolement_jour) as inscriptions;
\echo --- Impression des cartes (lot 8, V15) : commandes, cartes, délais, annulations
select f.jour, z.code, f.demandes, f.envoyees, f.en_attente, f.rejetees, f.non_classees, f.annulees
from bi.fait_demande_impression_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
select f.jour, z.code, f.expediees, f.remises, f.remises_hors_ligne, f.remises_en_ligne, f.remises_support,
       f.remises_autre, f.a_remettre
from bi.fait_carte_jour f join bi.zone z on z.id = f.centre_id order by 1, 2;
select f.jour, z.code, f.classe_j, f.cartes from bi.fait_delai_carte_jour f join bi.zone z on z.id = f.centre_id order by 1, 2, 3;
select f.jour, z.code, f.motif, f.motif_libelle, f.demandes
from bi.fait_annulation_impression_jour f join bi.zone z on z.id = f.centre_id order by 1, 2, 3;
\echo --- contrôles de l’impression : statuts = demandes ; remises + à remettre = expédiées ; motifs = annulées
select (select sum(demandes) from bi.fait_demande_impression_jour) as demandes,
       (select sum(envoyees + en_attente + rejetees + non_classees) from bi.fait_demande_impression_jour) as statuts,
       (select sum(annulees) from bi.fait_demande_impression_jour) as annulees,
       (select sum(demandes) from bi.fait_annulation_impression_jour) as par_motif,
       (select sum(expediees) from bi.fait_carte_jour) as expediees,
       (select sum(remises + a_remettre) from bi.fait_carte_jour) as remises_et_a_remettre,
       (select sum(cartes) from bi.fait_delai_carte_jour) as avec_delai;
