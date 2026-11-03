-- Délai du NIU à la carte (I-DELAI) : par jour d'expédition et centre, l'histogramme ne compte jamais plus de cartes
-- que les remises (une carte remise sans date de remise ou sans NIU n'y est pas). Renvoie les lignes en écart.
with delais as (
    select jour, code_centre, sum(cartes) as cartes
    from {{ ref('fait_delai_carte_jour') }}
    group by 1, 2
)
select l.jour, l.code_centre, l.cartes, coalesce(c.remises, 0) as remises
from delais l
left join {{ ref('fait_carte_jour') }} c on c.jour = l.jour and c.code_centre = l.code_centre
where l.cartes > coalesce(c.remises, 0)
