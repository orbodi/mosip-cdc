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
  - erreurs_idps (lot 8d, migration V16) : commandes qui ont eu au moins une erreur d'envoi à l'IDPS
    (dwh.erreur_idps_commande), parmi les demandes ; erreurs_idps ≤ demandes.
  - Une commande sans date de réception n'y est pas (alerte sur suivi_carte.jour_commande).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre'], 'unique': True}]) }}

select
    s.jour_commande                                                     as jour,
    s.code_centre,
    cast(count(*) as integer)                                           as demandes,
    cast(count(*) filter (where s.statut = 'envoyee') as integer)       as envoyees,
    cast(count(*) filter (where s.statut = 'en_attente') as integer)    as en_attente,
    cast(count(*) filter (where s.statut = 'rejetee') as integer)       as rejetees,
    cast(count(*) filter (where s.statut = 'non_classee') as integer)   as non_classees,
    cast(count(*) filter (where s.annule_le is not null) as integer)    as annulees,
    cast(count(e.request_id) as integer)                                as erreurs_idps
from {{ ref('suivi_carte') }} s
left join {{ ref('erreur_idps_commande') }} e on e.request_id = s.request_id
where s.jour_commande is not null
group by 1, 2
