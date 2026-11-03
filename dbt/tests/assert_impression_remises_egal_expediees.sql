-- Cartes expédiées (contrainte de bi.fait_carte_jour, migration V15) : remises + à remettre = expédiées, et les modes
-- de remise forment une partition des remises. Renvoie les lignes en écart.
select jour, code_centre, expediees, remises, a_remettre
from {{ ref('fait_carte_jour') }}
where remises + a_remettre <> expediees
   or remises_hors_ligne + remises_en_ligne + remises_support + remises_autre <> remises
