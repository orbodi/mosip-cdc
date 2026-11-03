{#-
  Contrat du backend : bi.fait_demande_impression_jour (migration V15 de mosip-bi-reporting). Une ligne par jour de
  réception de la commande et centre ; lecture « cohorte » : les commandes reçues ce jour-là, dans leur statut
  d'aujourd'hui (I-DEM, I-ATT, I-REJ, I-ANN ; docs/indicateurs.md, section Impression des cartes).

  - jour : entry_date de la commande (UTC = heure de Lomé) ; code_centre : cinq premiers chiffres du RID, résolu en
    centre de bi.zone à la publication (« Centre non référencé » s'il est inconnu).
  - Statuts (prc_status) : envoyees (OK) + en_attente (NEW) + rejetees (KO) + non_classees = demandes (contrainte de
    bi, test assert_impression_statuts_egal_demandes).
  - annulees : commandes annulées (événement NEW-PRINT-CANCELED), comptées à part (décision du 02/11/2026) : elles
    restent aussi dans leur statut ; annulees ≤ demandes.
  - Une commande sans date de réception n'y est pas (alerte sur suivi_carte.jour_commande).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre'], 'unique': True}]) }}

select
    jour_commande                                                       as jour,
    code_centre,
    cast(count(*) as integer)                                           as demandes,
    cast(count(*) filter (where statut = 'envoyee') as integer)         as envoyees,
    cast(count(*) filter (where statut = 'en_attente') as integer)      as en_attente,
    cast(count(*) filter (where statut = 'rejetee') as integer)         as rejetees,
    cast(count(*) filter (where statut = 'non_classee') as integer)     as non_classees,
    cast(count(*) filter (where annule_le is not null) as integer)      as annulees
from {{ ref('suivi_carte') }}
where jour_commande is not null
group by 1, 2
