{#-
  Listes de valeurs MOSIP (master.dynamic_field) : une ligne par champ et par code, libellé français de préférence.
  value_json est un tableau [{"code": …, "value": …, "langCode": …, "active": …}] ; « active » vaut true ou "true".
  Seuls les champs de la variable champs_dynamiques (dbt_project.yml) sont lus : un champ mal formé ailleurs ne
  bloque pas le calcul.
-#}
{{ config(indexes=[{'columns': ['champ', 'code'], 'unique': True}]) }}

with evenements as (

    select *
    from {{ source('lake', 'mosip_master_dynamic_field') }}
    where name in ({% for c in var('champs_dynamiques') %}'{{ c }}'{% if not loop.last %}, {% endif %}{% endfor %})

),

dernier as (

    select distinct on (id) id, __op
    from evenements
    order by id, __connect_offset desc

),

connu as (

    select distinct on (id) *
    from evenements
    where __op <> 'd'
    order by id, __connect_offset desc

),

valeurs as (

    select
        c.name                                          as champ,
        c.lang_code                                     as langue,
        v ->> 'code'                                    as code,
        v ->> 'value'                                   as libelle,
        coalesce(lower(v ->> 'active') = 'true', true)  as actif
    from connu c
    join dernier d using (id)
    cross join lateral json_array_elements(cast(c.value_json as json)) as v
    where d.__op <> 'd'

)

select distinct on (champ, code)
    champ,
    code,
    libelle,
    actif
from valeurs
order by champ, code, (langue = 'fra') desc, langue
