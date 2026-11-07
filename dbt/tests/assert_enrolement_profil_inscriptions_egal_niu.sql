-- Profil des inscriptions (fait_enrolement_jour, lot E2 de l'Exploration) : ses NIU ont, par sexe et par nationalité,
-- les mêmes nombres que le profil des NIU (fait_niu_profil_jour) ; seul l'âge diffère (au jour de réception ici, au
-- jour du NIU là). Renvoie les écarts.
with cohorte as (
    select sexe, nationalite, sum(niu_generes) as niu from {{ ref('fait_enrolement_jour') }} group by 1, 2
),
profil as (
    select sexe, nationalite, sum(niu_generes) as niu from {{ ref('fait_niu_profil_jour') }} group by 1, 2
)
select coalesce(c.sexe, p.sexe) as sexe, coalesce(c.nationalite, p.nationalite) as nationalite,
       coalesce(c.niu, 0) as niu_cohorte, coalesce(p.niu, 0) as niu_profil
from cohorte c
full join profil p on p.sexe = c.sexe and p.nationalite = c.nationalite
where coalesce(c.niu, 0) <> coalesce(p.niu, 0)
