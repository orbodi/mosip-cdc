-- Commandes d'impression (contrainte de bi.fait_demande_impression_jour, migration V15) : par jour et centre, les
-- statuts forment une partition des demandes ; les annulées et les commandes en erreur d'envoi à l'IDPS (comptées
-- à part, lot 8d) en sont des parties.
-- Renvoie les lignes en écart.
select jour, code_centre, demandes, envoyees, en_attente, rejetees, non_classees, annulees, erreurs_idps
from {{ ref('fait_demande_impression_jour') }}
where envoyees + en_attente + rejetees + non_classees <> demandes
   or annulees < 0 or annulees > demandes
   or erreurs_idps < 0 or erreurs_idps > demandes
