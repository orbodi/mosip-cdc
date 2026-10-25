{#-
  Synchronisations des paquets (regprc.registration_list), lues dans l'ODS : une ligne par synchronisation. Un RID peut
  être synchronisé deux fois (1 224 cas au relevé, étape 4).

  - synchronise_le : cr_dtimes, synchronisation du paquet par le poste d'enrôlement.
  - refuse_au_poste : client_status_code = REJECTED, décision prise au poste (relevé étape 5 : ces paquets finissent
    rejetés à l'étape VALIDATE_PACKET).
-#}
{{ config(materialized='view') }}

select
    id                                          as synchronisation_id,
    reg_id                                      as rid,
    nullif(reg_type, '')                        as reg_type,
    nullif(client_status_code, '')              as decision_poste,
    client_status_code = 'REJECTED'             as refuse_au_poste,
    cr_dtimes at time zone 'UTC'                as synchronise_le,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'regprc_registration_list') }}
where reg_id is not null
  and coalesce(__deleted, 'false') <> 'true'
