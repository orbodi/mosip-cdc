{#-
  Histogrammes des délais (I8, I9 ; cartes « Délais de traitement », colonne « Délai médian » du Territoire, onglet
  « Remontée la plus lente »). Futur contrat bi.fait_delai_jour (migration V7).
  Une ligne par jour, centre, type de demande, mesure et classe de délai, avec le nombre de paquets.

  - mesure reception_niu : de la réception au NIU (niu_le − recu_le), au jour du NIU ;
    mesure enrolement_reception : de l'enrôlement au poste à la réception (recu_le − enrole_le), au jour de réception.
  - classe_h : borne basse de la classe, en heures : heure par heure de 0 à 47, puis jour par jour (48, 72, 96…).
    Un délai négatif (horloges décalées) compte dans la classe 0.
  - Les histogrammes s'additionnent : la médiane et le 90e centile se calculent pour toute zone et toute période, à
    l'heure près sous 48 h et au jour près au-delà.
  - Contrôle : chaque mesure compte tous les paquets concernés.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande', 'mesure', 'classe_h'], 'unique': True}]) }}

with delais as (

    select jour_niu as jour, code_centre, type_demande, cast('reception_niu' as text) as mesure,
           extract(epoch from niu_le - recu_le) / 3600.0 as heures
    from {{ ref('suivi_inscription') }}
    where devenir = 'niu'

    union all

    select jour_reception, code_centre, type_demande, cast('enrolement_reception' as text),
           extract(epoch from recu_le - enrole_le) / 3600.0
    from {{ ref('suivi_inscription') }}
    where devenir <> 'non_recu'
      and enrole_le is not null

)

select
    jour,
    code_centre,
    type_demande,
    mesure,
    cast(case when heures < 48 then floor(greatest(heures, 0))
              else floor(heures / 24) * 24 end as integer)  as classe_h,
    cast(count(*) as integer)                               as paquets
from delais
group by 1, 2, 3, 4, 5
