{#-
  Historique des statuts : une ligne par période de statut. valid_to est vide pour le statut en cours.

  Date d'un changement :
  - observé par la capture (événements c et u) : heure exacte du commit dans MOSIP (cdc_ts) ;
  - présent au snapshot du 21/10/2026 (événements r) : estimée par la dernière modification
    (upd_dtimes), sinon par la création. date_estimee = true signale ces lignes.
-#}
with changes as (

    select
        prereg_id,
        status_code,
        case when cdc_op = 'r' then coalesce(updated_at, created_at)
             else cdc_ts
        end                                                                   as changed_at,
        cdc_op = 'r'                                                          as date_estimee,
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
    lead(changed_at) over (partition by prereg_id order by kafka_offset)  as valid_to,
    date_estimee
from changes
where previous_status is distinct from status_code
