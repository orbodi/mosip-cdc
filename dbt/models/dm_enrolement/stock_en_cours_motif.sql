{#-
  Paquets en cours par étape (reg_stage_name), motif (status_comment rangé par motif_inscription) et ancienneté :
  colonne « En cours » du bloc « Où s'arrêtent les paquets » (décision du 26/10/2026). Stock à l'heure du passage.
  Contrat bi.stock_en_cours_motif (migration V9 du backend).

  - anciennete : depuis la dernière transaction, comme stock_en_cours (moins_7j, 7_30j, plus_30j = bloqués).
  - Libellés : comme fait_arret_motif_jour.
  - Contrôle (assert_enrolement_motifs_egal_devenir) : total = en_cours de fait_enrolement_jour.
-#}
{{ config(indexes=[{'columns': ['code_centre', 'type_demande', 'stage', 'motif', 'anciennete'], 'unique': True}]) }}

select
    s.code_centre,
    s.type_demande,
    coalesce(m.stage, 'INCONNUE')                           as stage,
    coalesce(st.libelle, m.stage, 'Étape inconnue')         as stage_libelle,
    coalesce(st.ordre, 999)                                 as stage_ordre,
    coalesce(m.motif, 'AUTRE')                              as motif,
    coalesce(mo.libelle, 'Motif non répertorié')            as motif_libelle,
    mo.commentaire                                          as motif_commentaire,
    case
        when s.derniere_transaction_le >= now() - interval '7 days'  then 'moins_7j'
        when s.derniere_transaction_le >= now() - interval '30 days' then '7_30j'
        else 'plus_30j'
    end                                                     as anciennete,
    cast(count(*) as integer)                               as inscriptions,
    now()                                                   as calcule_le
from {{ ref('suivi_inscription') }} s
left join {{ ref('motif_inscription') }} m on m.rid = s.rid
left join {{ ref('ref_regprc_stages') }} st on st.stage = m.stage
left join {{ ref('ref_regprc_motifs') }} mo on mo.motif = coalesce(m.motif, 'AUTRE')
where s.devenir = 'en_cours'
group by 1, 2, 3, 4, 5, 6, 7, 8, 9
