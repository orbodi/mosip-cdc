{#-
  État courant de regprc.registration : une ligne par inscription reçue par MOSIP (RID), lue dans l'ODS
  (connecteur ods-regprc-registration, mis à jour sur place).

  - recu_le : cr_dtimes, réception du paquet par MOSIP (le jour d'une inscription ; pkt_cr_dtimes est toujours vide,
    relevé étape 1).
  - etape_code / etape_statut : dernière transaction (latest_trn_type_code / latest_trn_status_code) ; c'est l'étape
    où l'inscription se trouve ou s'est arrêtée. Le statut de l'inscription est status_code seul (relevé étape 2).
  - kafka_offset : offset du dernier message reçu pour cette inscription ; suivi_inscription ne relit que les lignes
    plus récentes que son dernier passage.
  - commentaire : status_comment, motif écrit par MOSIP (texte technique en anglais, capté depuis le 27/10/2026, sans
    identifiant de personne : relevé R13). Il ne sort pas du data warehouse : motif_inscription le range en motifs.
  - Horodatages MOSIP en UTC (heure de Lomé).
-#}
{{ config(materialized='view') }}

select
    id                                          as rid,
    nullif(reg_type, '')                        as reg_type,
    nullif(status_code, '')                     as status_code,
    nullif(latest_trn_type_code, '')            as etape_code,
    nullif(latest_trn_status_code, '')          as etape_statut,
    latest_trn_dtimes at time zone 'UTC'        as derniere_transaction_le,
    nullif(reg_stage_name, '')                  as reg_stage_name,
    nullif(status_comment, '')                  as commentaire,
    cr_dtimes  at time zone 'UTC'               as recu_le,
    upd_dtimes at time zone 'UTC'               as modifie_le,
    coalesce(__deleted, 'false') = 'true'       as supprime,
    __kafka_offset                              as kafka_offset
from {{ source('ods', 'regprc_registration') }}
where id is not null
