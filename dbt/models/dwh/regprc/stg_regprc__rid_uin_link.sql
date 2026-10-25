{#-
  Lien inscription → NIU (regprc.rid_uin_link, table propre à l'ANID), lu dans l'ODS : une ligne par RID.
  Le NIU lui-même (uin) et le numéro d'état civil ne sont jamais captés.

  - niu_le : entry_date, heure de génération du NIU (relevé étape 3 : toujours dans l'heure qui précède la transaction
    UIN_GENERATOR ; exacte pour tout l'historique).
  - Toute inscription qui a un lien compte « NIU générés », quel que soit son statut (décision A du 25/10/2026).
-#}
{{ config(materialized='view') }}

select
    reg_id                                      as rid,
    nullif(reg_type, '')                        as type_lien,
    entry_date at time zone 'UTC'               as niu_le,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'regprc_rid_uin_link') }}
where reg_id is not null
  and coalesce(__deleted, 'false') <> 'true'
