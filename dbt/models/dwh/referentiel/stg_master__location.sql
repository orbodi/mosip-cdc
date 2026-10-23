{#-
  Lieux MOSIP (master.location) depuis le lake : une ligne par code, dernier état connu, libellé français de
  préférence. Un lieu supprimé dans MOSIP garde son dernier état connu (supprime = vrai). Pays : niveau vide.
-#}
{{ config(indexes=[{'columns': ['code'], 'unique': True}]) }}

with evenements as (

    select * from {{ source('lake', 'mosip_master_location') }}

),

dernier as (

    select distinct on (code, lang_code) code, lang_code, __op
    from evenements
    order by code, lang_code, __connect_offset desc

),

connu as (

    select distinct on (code, lang_code) *
    from evenements
    where __op <> 'd'
    order by code, lang_code, __connect_offset desc

)

select distinct on (c.code)
    c.code,
    c.name                                              as nom,
    c.hierarchy_level,
    case c.hierarchy_level
        when 1 then 'region'
        when 2 then 'prefecture'
        when 3 then 'commune'
        when 4 then 'canton'
        when 5 then 'localite'
    end                                                 as niveau,
    c.parent_loc_code,
    c.is_active                                         as actif,
    d.__op = 'd' or coalesce(c.is_deleted, false)       as supprime
from connu c
join dernier d using (code, lang_code)
order by c.code, (c.lang_code = 'fra') desc, c.lang_code
