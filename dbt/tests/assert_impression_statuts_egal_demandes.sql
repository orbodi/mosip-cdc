-- Commandes d'impression (contrainte de bi.fait_demande_impression_jour, migration V15) : par jour et centre, les
-- statuts forment une partition des demandes, et les annulées (comptées à part) en sont une partie.
-- Renvoie les lignes en écart.
select jour, code_centre, demandes, envoyees, en_attente, rejetees, non_classees, annulees
from {{ ref('fait_demande_impression_jour') }}
where envoyees + en_attente + rejetees + non_classees <> demandes
   or annulees < 0 or annulees > demandes
