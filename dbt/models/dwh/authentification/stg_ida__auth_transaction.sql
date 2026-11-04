{#-
  État courant de ida.auth_transaction (lot 9), lu dans l'ODS (connecteur ods-ida-auth-transaction, upsert) : une
  ligne par authentification. Relevé et décisions : docs/releve-authentification.md.

  - authentifie_le : cr_dtimes, enregistrement par IDA (seul horodatage indexé et rempli par MOSIP ; UTC).
  - auth_type_code : liste de modalités séparées par des virgules (FINGERPRINT-AUTH,IRIS-AUTH…), rangée par
    seeds/ref_ida_modalites.csv dans le modèle authentification.
  - status_code : Y (réussie), N (échouée).
  - commentaire : status_comment, message fixe d'IDA ; rangé en motif (seeds/ref_ida_motifs.csv), il ne sort pas du
    data warehouse.
  - appelant_id, appelant_nom : partenaire (requested_entity_type PARTNER) ou client MOSIP (INTERNAL) ; noms
    d'organisation ou de service, jamais de personne.
  - Jamais captés : ref_id, token_id, static_tkn_id, signatures, request_trn_id.
-#}
{{ config(materialized='view') }}

select
    id                                          as transaction_id,
    cr_dtimes at time zone 'UTC'                as authentifie_le,
    nullif(auth_type_code, '')                  as auth_type_code,
    nullif(status_code, '')                     as status_code,
    nullif(status_comment, '')                  as commentaire,
    nullif(requested_entity_type, '')           as type_appelant,
    nullif(requested_entity_id, '')             as appelant_id,
    nullif(requested_entity_name, '')           as appelant_nom,
    coalesce(is_deleted, false)                 as supprime,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'ida_auth_transaction') }}
where id is not null
  and coalesce(__deleted, 'false') <> 'true'
