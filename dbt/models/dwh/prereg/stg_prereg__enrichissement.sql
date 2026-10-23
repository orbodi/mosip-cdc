{#-
  Dernier enrichissement connu de chaque dossier (API de pré-inscription MOSIP, job Spark).
  sexe : F (genre FLE), H (MLE), I pour tout autre genre ou genre absent.
-#}
{{ config(indexes=[{'columns': ['prereg_id'], 'unique': True}]) }}

select distinct on (prereg_id)
    prereg_id,
    genre,
    case upper(genre) when 'FLE' then 'F' when 'MLE' then 'H' else 'I' end   as sexe,
    nationalite,
    annee_naissance,
    mois_naissance,
    region_code,
    prefecture_code,
    commune_code,
    canton_code,
    localite_code,
    enrichi_le at time zone 'UTC'                                           as enrichi_le
from {{ source('lake', 'mosip_prereg_enrichissement') }}
order by prereg_id, enrichi_le desc, __connect_offset desc
