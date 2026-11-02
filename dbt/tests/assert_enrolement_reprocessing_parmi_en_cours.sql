-- Les dossiers en reprocessing sont une partie des en cours (contrainte de bi.fait_enrolement_jour, migration V13) :
-- jamais négatifs, jamais plus nombreux que les en cours de la même ligne. Renvoie les lignes en écart.
select *
from {{ ref('fait_enrolement_jour') }}
where en_reprocessing < 0 or en_reprocessing > en_cours
