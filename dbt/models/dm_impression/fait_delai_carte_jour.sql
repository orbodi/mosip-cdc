{#-
  Contrat du backend : bi.fait_delai_carte_jour (migration V15). Histogramme du délai du NIU à la carte remise (I-DELAI)
  : une ligne par jour d'expédition, centre et classe de délai, avec le nombre de cartes remises.

  - délai : première date de remise − génération du NIU (rid_uin_link.entry_date), en jours entiers ; un délai
    négatif (horloges décalées) compte dans la classe 0.
  - classe_j : borne basse de la classe, en jours : jour par jour de 0 à 89, puis par 30 jours (90, 120… 690), puis
    720 pour deux ans et plus. Les histogrammes s'additionnent : la médiane se calcule pour toute zone et toute
    période, au jour près sous 90 jours.
  - Même cohorte que fait_carte_jour (jour d'expédition) : le délai porte sur les cartes remises de la période.
    Une carte remise sans date de remise ou sans NIU n'y est pas : total ≤ remises (test
    assert_impression_delais_parmi_remises).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'classe_j'], 'unique': True}]) }}

with delais as (

    select
        jour_expedition                                                 as jour,
        code_centre,
        floor(extract(epoch from remis_le - niu_le) / 86400.0)          as jours
    from {{ ref('suivi_carte') }}
    where remise
      and jour_expedition is not null
      and remis_le is not null
      and niu_le is not null

)

select
    jour,
    code_centre,
    cast(case
        when jours < 0   then 0
        when jours < 90  then jours
        when jours < 720 then floor(jours / 30) * 30
        else 720
    end as integer)                                                     as classe_j,
    cast(count(*) as integer)                                           as cartes
from delais
group by 1, 2, 3
