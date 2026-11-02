-- Les dossiers en reprocessing sont une partie des en cours (contraintes de bi : migrations V13 pour
-- fait_enrolement_jour, V14 pour stock_en_cours_motif) : jamais négatifs, jamais plus nombreux que les paquets en cours
-- de la même ligne. Renvoie les lignes en écart.
select 'fait_enrolement_jour' as modele, code_centre, type_demande, en_cours as paquets, en_reprocessing
from {{ ref('fait_enrolement_jour') }}
where en_reprocessing < 0 or en_reprocessing > en_cours
union all
select 'stock_en_cours_motif', code_centre, type_demande, inscriptions, en_reprocessing
from {{ ref('stock_en_cours_motif') }}
where en_reprocessing < 0 or en_reprocessing > inscriptions
