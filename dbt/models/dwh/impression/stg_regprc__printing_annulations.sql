{#-
  Annulations de commandes d'impression (lot 8) : événements NEW-PRINT-CANCELED de regprc.printing_orders_details, lus
  dans le lake (connecteur lake-regprc-printing-orders-details, une ligne par événement, jamais modifiée). Le snapshot
  du 02/11/2026 a chargé toutes les annulations de l'historique (693).

  - annule_le : cr_dtimes de l'événement ; reason_code : motif (CANCEL_PHOTO…, seeds/ref_impression_motifs_annulation.csv).
  - connect_offset : offset Kafka de l'événement ; suivi_carte ne relit que les annulations plus récentes que son
    dernier passage.
  - Le texte libre details et l'auteur cr_by ne sont jamais captés.
-#}
{{ config(materialized='view') }}

select
    nullif(request_id, '')                      as request_id,
    nullif(reason_code, '')                     as reason_code,
    cr_dtimes at time zone 'UTC'                as annule_le,
    __connect_offset                            as connect_offset
from {{ source('lake', 'mosip_regprc_printing_orders_details') }}
where status_code = 'NEW-PRINT-CANCELED'
  and request_id is not null
  and coalesce(__deleted, 'false') <> 'true'
