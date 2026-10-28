{#-
  Rejets et échecs par étape (reg_stage_name) et motif (status_comment rangé par motif_inscription) : bloc « Où
  s'arrêtent les paquets », décision du 26/10/2026. Contrat bi.fait_arret_motif_jour (migration V9 du backend).
  Une ligne par jour de réception, centre, type de demande, devenir (rejete, echoue), étape et motif.

  - stage_libelle, stage_ordre : seeds/ref_regprc_stages.csv, ou le nom de l'étape et 999 si elle n'y est pas.
  - motif_libelle, motif_commentaire : seeds/ref_regprc_motifs.csv (le commentaire est le message type de MOSIP du
    catalogue, jamais le texte de l'inscription).
  - Une inscription sans ligne dans motif_inscription (devenue PROCESSED entre les deux modèles) compte en AUTRE : les
    totaux restent ceux du Devenir.
  - Contrôle (assert_enrolement_motifs_egal_devenir) : par devenir, la somme égale les rejetees et echouees de
    fait_enrolement_jour.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande', 'devenir', 'stage', 'motif'], 'unique': True}]) }}

select
    s.jour_reception                                        as jour,
    s.code_centre,
    s.type_demande,
    s.devenir,
    coalesce(m.stage, 'INCONNUE')                           as stage,
    coalesce(st.libelle, m.stage, 'Étape inconnue')         as stage_libelle,
    coalesce(st.ordre, 999)                                 as stage_ordre,
    coalesce(m.motif, 'AUTRE')                              as motif,
    coalesce(mo.libelle, 'Motif non répertorié')            as motif_libelle,
    mo.commentaire                                          as motif_commentaire,
    cast(count(*) as integer)                               as inscriptions
from {{ ref('suivi_inscription') }} s
left join {{ ref('motif_inscription') }} m on m.rid = s.rid
left join {{ ref('ref_regprc_stages') }} st on st.stage = m.stage
left join {{ ref('ref_regprc_motifs') }} mo on mo.motif = coalesce(m.motif, 'AUTRE')
where s.devenir in ('rejete', 'echoue')
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
