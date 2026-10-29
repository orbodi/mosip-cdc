{#-
  Région de chaque centre d'enrôlement, en remontant dim_zone (centre → localité … → préfecture → région).
  Un centre rattaché à HORS_REFERENTIEL, ou dont la chaîne n'atteint pas une région, n'a pas de ligne : la publication
  le range sous « Hors référentiel ».
-#}
{{ config(indexes=[{'columns': ['code_centre'], 'unique': True}]) }}

with recursive montee as (

    select code as code_centre, code, niveau, parent_code, 0 as hauteur
    from {{ ref('dim_zone') }}
    where niveau = 'centre'

    union all

    select m.code_centre, z.code, z.niveau, z.parent_code, m.hauteur + 1
    from montee m
    join {{ ref('dim_zone') }} z on z.code = m.parent_code
    where m.niveau <> 'region'
      and m.hauteur < 10

)

select code_centre, min(code) as code_region
from montee
where niveau = 'region'
group by code_centre
