{#-
  Erreurs d'envoi des commandes à l'IDPS (lot 8d, I-ERR) : événements PRINT-REQUEST-ERR (raison
  CORE-PRINTING-IDPS-1) de regprc.printing_orders_details, lus dans le lake. Le snapshot du 02/11/2026 a chargé toutes
  les erreurs de l'historique (302 825 événements pour 172 354 commandes) ; MOSIP refait ensuite l'envoi.

  - erreur_le : cr_dtimes de l'événement. Le texte libre details et l'auteur cr_by ne sont jamais captés.
-#}
{{ config(materialized='view') }}

select
    nullif(request_id, '')                      as request_id,
    nullif(reason_code, '')                     as reason_code,
    cr_dtimes at time zone 'UTC'                as erreur_le,
    __connect_offset                            as connect_offset
from {{ source('lake', 'mosip_regprc_printing_orders_details') }}
where status_code = 'PRINT-REQUEST-ERR'
  and request_id is not null
  and coalesce(__deleted, 'false') <> 'true'
