-- Sur toute la durée, les NIU par jour d'aboutissement (fait_niu_jour, lecture flux) égalent les NIU par jour de
-- réception (fait_enrolement_jour, lecture cohorte), au total et par centre et type. Renvoie les écarts.
with flux as (
    select code_centre, type_demande, sum(niu_generes) as niu
    from {{ ref('fait_niu_jour') }}
    group by 1, 2
),
cohorte as (
    select code_centre, type_demande, sum(niu_generes) as niu
    from {{ ref('fait_enrolement_jour') }}
    group by 1, 2
)
select coalesce(f.code_centre, c.code_centre) as code_centre,
       coalesce(f.type_demande, c.type_demande) as type_demande,
       coalesce(f.niu, 0) as niu_flux,
       coalesce(c.niu, 0) as niu_cohorte
from flux f
full join cohorte c using (code_centre, type_demande)
where coalesce(f.niu, 0) <> coalesce(c.niu, 0)
