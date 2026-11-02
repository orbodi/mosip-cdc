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
  - en_reprocessing (migration V13, 31/10/2026) : dont en cours dont la dernière transaction MOSIP est REPROCESS
    (etape_statut = latest_trn_status_code) ; MOSIP les reprendra. Partie de en_cours, jamais un statut de plus :
    en_reprocessing ≤ en_cours (contrainte de bi, test assert_enrolement_reprocessing_parmi_en_cours). Un dossier
    échoué, rejeté ou non classé dont la dernière transaction est REPROCESS n'y compte pas (décision du 31/10/2026).
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
    cast(count(*) filter (where devenir = 'non_classe') as integer)     as non_classees,
    cast(count(*) filter (where devenir = 'en_cours' and etape_statut = 'REPROCESS') as integer)
                                                                        as en_reprocessing
from {{ ref('suivi_inscription') }}
where devenir <> 'non_recu'
group by 1, 2, 3, 4, 5
