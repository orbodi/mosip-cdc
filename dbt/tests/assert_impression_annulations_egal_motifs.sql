-- Annulations : par jour de réception et centre, la somme des motifs (bi.fait_annulation_impression_jour) égale les
-- annulées de bi.fait_demande_impression_jour. Renvoie les lignes en écart.
with motifs as (
    select jour, code_centre, sum(demandes) as annulees
    from {{ ref('fait_annulation_impression_jour') }}
    group by 1, 2
)
select coalesce(d.jour, m.jour) as jour, coalesce(d.code_centre, m.code_centre) as code_centre,
       coalesce(d.annulees, 0) as annulees, coalesce(m.annulees, 0) as par_motif
from (select jour, code_centre, annulees from {{ ref('fait_demande_impression_jour') }} where annulees > 0) d
full join motifs m on m.jour = d.jour and m.code_centre = d.code_centre
where coalesce(d.annulees, 0) <> coalesce(m.annulees, 0)
