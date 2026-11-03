{#-
  Contrat du backend : bi.fait_annulation_impression_jour (migration V15). Commandes annulées (I-ANN) par jour de
  réception de la commande, centre et motif (reason_code de l'événement NEW-PRINT-CANCELED).

  - Même cohorte que fait_demande_impression_jour : par jour et centre, somme des motifs = annulees (test
    assert_impression_annulations_egal_motifs).
  - motif : code MOSIP connu de seeds/ref_impression_motifs_annulation.csv, avec son libellé français ;
    NON_REPERTORIE (« Motif non répertorié ») sinon.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'motif'], 'unique': True}]) }}

select
    s.jour_commande                                                     as jour,
    s.code_centre,
    s.motif_annulation                                                  as motif,
    coalesce(min(m.libelle), 'Motif non répertorié')                    as motif_libelle,
    cast(count(*) as integer)                                           as demandes
from {{ ref('suivi_carte') }} s
left join {{ ref('ref_impression_motifs_annulation') }} m on m.motif = s.motif_annulation
where s.annule_le is not null
  and s.jour_commande is not null
group by 1, 2, 3
