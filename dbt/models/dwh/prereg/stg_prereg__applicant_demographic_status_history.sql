{#-
  Historique des statuts : une ligne par période de statut. valid_to est vide pour le statut en cours.
  Il commence au premier snapshot (21/10/2026) : pour un dossier plus ancien, seul son statut
  à cette date est connu, daté par sa dernière modification (upd_dtimes).
-#}
with changes as (

    select
        prereg_id,
        status_code,
        coalesce(updated_at, created_at, cdc_ts)                              as changed_at,
        kafka_offset,
        lag(status_code) over (partition by prereg_id order by kafka_offset)  as previous_status
    from {{ ref('stg_prereg__applicant_demographic_events') }}
    where cdc_op <> 'd'

)

select
    prereg_id,
    previous_status,
    status_code,
    changed_at                                                            as valid_from,
    lead(changed_at) over (partition by prereg_id order by kafka_offset)  as valid_to
from changes
where previous_status is distinct from status_code
