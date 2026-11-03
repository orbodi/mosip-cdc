{#-
  État courant de regprc.printing_shipped_cards (lot 8), lu dans l'ODS (connecteur ods-regprc-printing-shipped-cards) :
  une ligne par carte expédiée, mise à jour à sa remise. La remise est enregistrée dans MOSIP (relevé, étape 2).

  - expedie_le : entry_date, mise en boîte et expédition (I-EXP).
  - remise : delivery_status = DELIVERED (I-REM) ; NOT_DELIVERED = à remettre (I-AREM).
  - remis_le : delivery_date, remise au citoyen ; delivery_mode : OFFLINE, ONLINE, SUPPORT.
  - Numéros de carte et de colis, agent de remise et lieu de remise ne sont jamais captés (le lieu de remise est le
    centre du RID pour 6 088 386 cartes sur 6 088 392).
-#}
{{ config(materialized='view') }}

select
    id                                          as carte_id,
    nullif(request_id, '')                      as request_id,
    entry_date    at time zone 'UTC'            as expedie_le,
    nullif(delivery_status, '')                 as delivery_status,
    coalesce(delivery_status = 'DELIVERED', false) as remise,
    nullif(delivery_mode, '')                   as delivery_mode,
    delivery_date at time zone 'UTC'            as remis_le,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'regprc_printing_shipped_cards') }}
where id is not null
  and coalesce(__deleted, 'false') <> 'true'
