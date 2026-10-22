{#-
  Un jour par ligne, de la première pré-inscription jusqu'à un an après aujourd'hui.
  pg_catalog.date est écrit en entier : avec edb_redwood_date, EDB peut traduire "date" en timestamp(0).
-#}
{{ config(indexes=[{'columns': ['date_key'], 'unique': True}]) }}

with bornes as (

    select coalesce(
        cast(min(created_at) at time zone 'UTC' as pg_catalog.date),
        current_date
    ) as debut
    from {{ ref('stg_prereg__applicant_demographic') }}

),

jours as (

    select cast(j as pg_catalog.date) as date_jour
    from bornes,
         generate_series(debut, current_date + 365, interval '1 day') as j

)

select
    cast(to_char(date_jour, 'YYYYMMDD') as integer)  as date_key,
    date_jour,
    cast(extract(year    from date_jour) as integer) as annee,
    cast(extract(quarter from date_jour) as integer) as trimestre,
    cast(extract(month   from date_jour) as integer) as mois,
    to_char(date_jour, 'YYYY-MM')                    as annee_mois,
    cast(extract(isodow  from date_jour) as integer) as jour_semaine,
    extract(isodow from date_jour) in (6, 7)         as est_weekend
from jours
