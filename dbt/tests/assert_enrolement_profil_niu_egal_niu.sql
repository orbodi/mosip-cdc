-- Le profil des NIU (fait_niu_profil_jour, lot 6) compte exactement les NIU de fait_niu_jour, jour par jour : un NIU
-- pas encore enrichi y figure en sexe I, âge inconnu, nationalité « Non renseignée ». Renvoie les jours en écart.
with profil as (
    select jour, sum(niu_generes) as niu from {{ ref('fait_niu_profil_jour') }} group by 1
),
flux as (
    select jour, sum(niu_generes) as niu from {{ ref('fait_niu_jour') }} group by 1
)
select coalesce(p.jour, f.jour) as jour, coalesce(p.niu, 0) as niu_profil, coalesce(f.niu, 0) as niu_flux
from profil p
full join flux f using (jour)
where coalesce(p.niu, 0) <> coalesce(f.niu, 0)
