{#-
  Contrat du backend : bi.fait_preinscription_zone_jour (migration V6 de mosip-bi-reporting).
  Une ligne par jour de création et préfecture de résidence déclarée (code dim_zone). Les dossiers sans préfecture
  connue n'y figurent pas : le tableau Territoire ne compte que les demandes localisées.
-#}
{{ config(indexes=[{'columns': ['jour', 'zone_code'], 'unique': True}]) }}

select
    pg_catalog.date(cree_le at time zone 'UTC')     as jour,
    prefecture_code                                 as zone_code,
    cast(count(*) as integer)                       as demandes
from {{ ref('fct_preinscription') }}
where prefecture_code is not null
group by 1, 2
