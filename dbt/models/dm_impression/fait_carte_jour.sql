{#-
  Contrat du backend : bi.fait_carte_jour (migration V15). Une ligne par jour d'expédition de la carte et centre ;
  lecture « cohorte » : les cartes expédiées ce jour-là, remises ou non aujourd'hui (I-EXP, I-REM, I-AREM).

  - jour : première expédition de la carte (printing_shipped_cards.entry_date).
  - remises : cartes DELIVERED ; a_remettre : les autres. remises + a_remettre = expediees (contrainte de bi, test
    assert_impression_remises_egal_expediees). Remises en % des expédiées (décision du 02/11/2026).
  - Modes de remise : hors_ligne (OFFLINE) + en_ligne (ONLINE) + support (SUPPORT) + autre (mode absent ou inconnu)
    = remises.
  - L'ancienneté des cartes à remettre (bloc « Depuis quand ces cartes attendent ») se lit dans le jour
    d'expédition : l'API la calcule à l'heure de la lecture, sans stock à part.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre'], 'unique': True}]) }}

select
    jour_expedition                                                         as jour,
    code_centre,
    cast(count(*) as integer)                                               as expediees,
    cast(count(*) filter (where remise) as integer)                         as remises,
    cast(count(*) filter (where mode_remise = 'hors_ligne') as integer)     as remises_hors_ligne,
    cast(count(*) filter (where mode_remise = 'en_ligne') as integer)       as remises_en_ligne,
    cast(count(*) filter (where mode_remise = 'support') as integer)        as remises_support,
    cast(count(*) filter (where mode_remise = 'autre') as integer)          as remises_autre,
    cast(count(*) filter (where not remise) as integer)                     as a_remettre
from {{ ref('suivi_carte') }}
where jour_expedition is not null
group by 1, 2
