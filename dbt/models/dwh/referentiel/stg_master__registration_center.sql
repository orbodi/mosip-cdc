{#-
  Centres d'enrôlement MOSIP (master.registration_center) depuis le lake : une ligne par identifiant, dernier état
  connu, libellé français de préférence. Tous les centres, actifs, inactifs ou supprimés : l'historique des
  inscriptions doit toujours retrouver son centre.
-#}
{{ config(indexes=[{'columns': ['id'], 'unique': True}]) }}

with evenements as (

    select * from {{ source('lake', 'mosip_master_registration_center') }}

),

dernier as (

    select distinct on (id, lang_code) id, lang_code, __op
    from evenements
    order by id, lang_code, __connect_offset desc

),

connu as (

    select distinct on (id, lang_code) *
    from evenements
    where __op <> 'd'
    order by id, lang_code, __connect_offset desc

)

select distinct on (c.id)
    c.id,
    c.name                                              as nom,
    c.cntrtyp_code                                      as type_centre,
    c.location_code,
    c.zone_code,
    c.latitude,
    c.longitude,
    c.is_active                                         as actif,
    d.__op = 'd' or coalesce(c.is_deleted, false)       as supprime
from connu c
join dernier d using (id, lang_code)
order by c.id, (c.lang_code = 'fra') desc, c.lang_code
