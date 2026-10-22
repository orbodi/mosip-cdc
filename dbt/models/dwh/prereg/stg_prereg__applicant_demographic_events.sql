{#-
  Journal des événements, typé et sans doublon : une ligne par changement.
  Incrémental : chaque passage ne lit que les nouveaux offsets Kafka.
  Le topic n'a qu'une partition : l'offset suit l'ordre des changements.
  Si le topic est un jour recréé (offsets repartant de 0), reconstruire avec --full-refresh.
-#}
{{ config(
    materialized='incremental',
    incremental_strategy='append',
    indexes=[
      {'columns': ['event_id'], 'unique': True},
      {'columns': ['prereg_id', 'kafka_offset']}
    ]
) }}

with source as (

    select * from {{ source('lake', 'mosip_prereg_applicant_demographic') }}
    {% if is_incremental() %}
    where __connect_offset > (select coalesce(max(kafka_offset), -1) from {{ this }})
    {% endif %}

),

typed as (

    select
        prereg_id || ':' || __lsn || ':' || __op   as event_id,
        prereg_id,
        nullif(status_code, '')                    as status_code,
        lang_code,
        cr_dtimes  at time zone 'UTC'              as created_at,
        upd_dtimes at time zone 'UTC'              as updated_at,
        __op                                       as cdc_op,
        __lsn                                      as cdc_lsn,
        to_timestamp(__source_ts_ms / 1000.0)      as cdc_ts,
        __connect_offset                           as kafka_offset
    from source

),

deduped as (

    select distinct on (event_id) *
    from typed
    order by event_id, kafka_offset

)

select * from deduped
{% if is_incremental() %}
where not exists (select 1 from {{ this }} t where t.event_id = deduped.event_id)
{% endif %}
