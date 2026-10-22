{#-
  État courant : une ligne par dossier.
  Un dossier supprimé dans MOSIP reste présent, marqué is_deleted, avec ses dernières valeurs connues.
-#}
{{ config(indexes=[
    {'columns': ['prereg_id'], 'unique': True},
    {'columns': ['status_code']}
]) }}

with events as (

    select * from {{ ref('stg_prereg__applicant_demographic_events') }}

),

latest as (

    select distinct on (prereg_id) *
    from events
    order by prereg_id, kafka_offset desc

),

last_known as (

    select distinct on (prereg_id) *
    from events
    where cdc_op <> 'd'
    order by prereg_id, kafka_offset desc

)

select
    l.prereg_id,
    k.status_code,
    k.lang_code,
    k.created_at,
    k.updated_at,
    l.cdc_op = 'd'                              as is_deleted,
    case when l.cdc_op = 'd' then l.cdc_ts end  as deleted_at,
    l.cdc_ts                                    as last_change_at
from latest l
left join last_known k using (prereg_id)
