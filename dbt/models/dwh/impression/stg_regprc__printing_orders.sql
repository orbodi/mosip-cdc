{#-
  État courant de regprc.printing_orders (lot 8), lu dans l'ODS (connecteur ods-regprc-printing-orders, mis à jour sur
  place) : une ligne par commande d'impression. Relevé : docs/releve-impression.md.

  - commande_le : entry_date, réception de la commande (le jour d'une demande d'impression, I-DEM).
  - envoye_le : issuing_date, envoi à l'imprimeur (vide tant que la commande est NEW).
  - prc_status : NEW (en attente), OK (envoyée), KO (rejetée), regroupé par seeds/ref_impression_statuts.csv.
  - rid : centre d'enrôlement (5 premiers chiffres) et lien avec le NIU ; ne sort pas du data warehouse.
  - Le NIU (uin), le nombre de doigts et le nom du centre ne sont jamais captés. Horodatages MOSIP en UTC.
-#}
{{ config(materialized='view') }}

select
    id                                          as commande_id,
    rid,
    nullif(request_id, '')                      as request_id,
    nullif(prc_status, '')                      as prc_status,
    entry_date   at time zone 'UTC'             as commande_le,
    issuing_date at time zone 'UTC'             as envoye_le,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'regprc_printing_orders') }}
where id is not null
  and coalesce(__deleted, 'false') <> 'true'
