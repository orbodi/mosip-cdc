{#-
  Contrat du backend : bi.fait_enrolement_jour (migrations V1 et V2 de mosip-bi-reporting).
  Une ligne par jour de réception, centre (code) et type de demande ; lecture « cohorte » : les paquets reçus ce
  jour-là, dans leur devenir d'aujourd'hui (I1, I2 cohorte, I4).

  - jour : réception par MOSIP (cr_dtimes, UTC = heure de Lomé).
  - code_centre : résolu en centre de bi.zone à la publication (« Centre non référencé » s'il est inconnu).
  - sexe I et tranche inconnu : jusqu'à l'enrichissement démographique (lot 6).
  - devenir : règle I4 de dwh.suivi_inscription. Contrôle :
    niu_generes + en_cours + echouees + rejetees + non_classees = inscriptions.
  - Paquets synchronisés mais pas encore reçus : exclus (ils n'ont pas de jour de réception ; voir
    stock_synchro_non_recue).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande'], 'unique': True}]) }}

select
    jour_reception                                                      as jour,
    code_centre,
    cast('I' as text)                                                   as sexe,
    cast('inconnu' as text)                                             as tranche_age,
    type_demande,
    cast(count(*) as integer)                                           as inscriptions,
    cast(count(*) filter (where devenir = 'niu') as integer)            as niu_generes,
    cast(count(*) filter (where devenir = 'en_cours') as integer)       as en_cours,
    cast(count(*) filter (where devenir = 'echoue') as integer)         as echouees,
    cast(count(*) filter (where devenir = 'rejete') as integer)         as rejetees,
    cast(count(*) filter (where devenir = 'non_classe') as integer)     as non_classees
from {{ ref('suivi_inscription') }}
where devenir <> 'non_recu'
group by 1, 2, 3, 4, 5
