{#-
  Territoire du tableau de bord (contrat bi.zone) : régions, préfectures, communes, cantons et localités
  (master.location), puis centres d'enrôlement (master.registration_center). Une ligne par code.

  - parent_code : code du niveau supérieur ; vide pour une région. Une zone dont le parent est inconnu, ou un
    centre rattaché au pays, va sous HORS_REFERENTIEL (zone créée par le backend).
  - nom : libellé de seeds/ref_zone_libelles.csv s'il existe ; sinon le nom MOSIP, en majuscules initiales pour
    les lieux, tel quel pour les centres (sigles EPP, EPC…).
-#}
{{ config(indexes=[{'columns': ['code'], 'unique': True}]) }}

with lieux as (

    select code, niveau, initcap(nom) as nom, parent_loc_code
    from {{ ref('stg_master__location') }}
    where niveau is not null

),

centres as (

    select id as code, 'centre' as niveau, nom, location_code as parent_loc_code
    from {{ ref('stg_master__registration_center') }}

),

zones as (

    select * from lieux
    union all
    select * from centres

)

select
    z.code,
    z.niveau,
    coalesce(l.nom, z.nom, z.code)                  as nom,
    case
        when z.niveau = 'region' then null
        when p.code is not null  then p.code
        else 'HORS_REFERENTIEL'
    end                                             as parent_code,
    0                                               as ordre
from zones z
left join lieux p on p.code = z.parent_loc_code
left join {{ ref('ref_zone_libelles') }} l on l.code = z.code
