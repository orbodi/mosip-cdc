{#-
  Rejets et échecs par étape (I5, I6 ; bloc « Où s'arrêtent les paquets »). Futur contrat bi.fait_arret_etape_jour
  (migration V7).
  Une ligne par jour de réception, centre, type de demande, devenir (rejete, echoue) et étape.

  - etape : code d'étape (REFUS_POSTE pour un refus au poste, décision B) ; libellé et ordre de ref_regprc_etapes, ou le
    code lui-même et l'ordre 999 pour une étape inconnue (alerte du test de suivi_inscription).
  - Les étapes à faible effectif sont regroupées en « Autres étapes » par l'API, pas ici.
  - Contrôle : par devenir, la somme des étapes égale les rejetees et echouees de fait_enrolement_jour.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande', 'devenir', 'etape'], 'unique': True}]) }}

select
    s.jour_reception                                as jour,
    s.code_centre,
    s.type_demande,
    s.devenir,
    coalesce(s.etape, 'INCONNUE')                   as etape,
    coalesce(e.libelle, s.etape, 'Étape inconnue')  as etape_libelle,
    coalesce(e.ordre, 999)                          as etape_ordre,
    cast(count(*) as integer)                       as inscriptions
from {{ ref('suivi_inscription') }} s
left join {{ ref('ref_regprc_etapes') }} e on e.code = s.etape
where s.devenir in ('rejete', 'echoue')
group by 1, 2, 3, 4, 5, 6, 7
