{#-
  État courant de ida.otp_transaction (lot 9), lu dans l'ODS (connecteur ods-ida-otp-transaction, upsert) : un code
  OTP demandé par ligne. status_code : active (jamais utilisé, expiré ensuite), used (utilisé). demande_le :
  cr_dtimes (generated_dtimes est toujours vide dans MOSIP, relevé du 04/11/2026). Jamais captés : ref_id, otp_hash.
-#}
{{ config(materialized='view') }}

select
    id                                          as code_id,
    cr_dtimes at time zone 'UTC'                as demande_le,
    expiry_dtimes at time zone 'UTC'            as expire_le,
    nullif(status_code, '')                     as status_code,
    coalesce(is_deleted, false)                 as supprime,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'ida_otp_transaction') }}
where id is not null
  and coalesce(__deleted, 'false') <> 'true'
