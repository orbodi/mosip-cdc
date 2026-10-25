{#-
  Table pivot de l'enrôlement : une ligne par RID connu de MOSIP, reçu (registration) ou seulement synchronisé
  (registration_list). Tous les faits de dm_enrolement et le suivi d'un dossier en sont tirés.

  Jalons :
  - enrole_le : horodatage contenu dans le RID (14 derniers chiffres, AAAAMMJJHHMISS), heure de création du paquet au
    poste (relevé étape 6) ; nul si le RID n'a pas ce format ;
  - synchronise_le : première synchronisation ; refus_poste : une synchronisation au moins est REJECTED ;
  - recu_le : réception par MOSIP ; niu_le : génération du NIU (rid_uin_link.entry_date).

  Devenir (règle I4, partition exacte des paquets reçus) :
  - niu : a un lien dans rid_uin_link, quel que soit son statut (décision A) ;
  - sinon selon status_code (seeds/ref_regprc_statuts.csv) : en_cours (PROCESSING, ERROR), echoue (FAILED,
    PACKET_UPLOADER_FAILED), rejete (REJECTED) ; tout autre cas = non_classe, jamais deviné (alerte) ;
  - non_recu : synchronisé, pas encore reçu par MOSIP (I10).

  etape : étape d'arrêt ou de présence (etape_code), sauf un rejet à VALIDATE_PACKET d'un paquet refusé au poste,
  noté REFUS_POSTE (décision B : le refus est compté avec les rejets, sous le nom de son étape).

  Incrémental : à chaque passage, seuls les RID touchés depuis le passage précédent sont recalculés (delete+insert),
  repérés par l'offset Kafka de chacune des trois sources. Les chiffres qui dépendent de l'heure (ancienneté,
  « bloqués ») ne sont PAS stockés ici, mais calculés dans les faits de dm_enrolement à chaque passage.
  maj_le : heure du passage qui a écrit la ligne ; la publication du suivi d'un dossier ne reprend que les lignes
  écrites depuis sa dernière publication.

  Le RID reste dans le data warehouse ; vers bi, seule son empreinte HMAC est publiée (suivi d'un dossier).
-#}
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='rid',
    indexes=[
      {'columns': ['rid'], 'unique': True},
      {'columns': ['maj_le']},
      {'columns': ['devenir']},
      {'columns': ['jour_reception', 'code_centre']}
    ]
) }}

with

{% if is_incremental() %}
reperes as (

    select
        coalesce(max(offset_inscription), -1)   as offset_inscription,
        coalesce(max(offset_lien), -1)          as offset_lien,
        coalesce(max(offset_synchro), -1)       as offset_synchro
    from {{ this }}

),

rids as (

    select r.rid from {{ ref('stg_regprc__registration') }} r, reperes p where r.kafka_offset > p.offset_inscription
    union
    select l.rid from {{ ref('stg_regprc__rid_uin_link') }} l, reperes p where l.kafka_offset > p.offset_lien
    union
    select s.rid from {{ ref('stg_regprc__registration_list') }} s, reperes p where s.kafka_offset > p.offset_synchro

),
{% else %}
rids as (

    select rid from {{ ref('stg_regprc__registration') }}
    union
    select rid from {{ ref('stg_regprc__registration_list') }}

),
{% endif %}

synchro as (

    select
        s.rid,
        min(s.synchronise_le)                   as synchronise_le,
        count(*)                                as nb_synchronisations,
        bool_or(s.refuse_au_poste)              as refus_poste,
        min(s.reg_type)                         as reg_type,
        max(s.kafka_offset)                     as offset_synchro
    from {{ ref('stg_regprc__registration_list') }} s
    join rids using (rid)
    group by s.rid

),

base as (

    select
        k.rid,
        r.rid is not null                       as recu,
        coalesce(r.reg_type, s.reg_type)        as type_demande,
        right(k.rid, 14)                        as horodatage,
        s.synchronise_le,
        coalesce(s.nb_synchronisations, 0)      as nb_synchronisations,
        coalesce(s.refus_poste, false)          as refus_poste,
        r.recu_le,
        l.niu_le,
        l.type_lien,
        r.status_code,
        r.etape_code,
        r.etape_statut,
        r.derniere_transaction_le,
        r.kafka_offset                          as offset_inscription,
        l.kafka_offset                          as offset_lien,
        s.offset_synchro
    from rids k
    left join {{ ref('stg_regprc__registration') }} r using (rid)
    left join {{ ref('stg_regprc__rid_uin_link') }} l using (rid)
    left join synchro s using (rid)
    where r.rid is not null or s.rid is not null

)

select
    b.rid,
    left(b.rid, 5)                                                          as code_centre,
    left(b.rid, 10)                                                         as code_poste,
    coalesce(b.type_demande, 'inconnu')                                     as type_demande,
    case
        when b.horodatage ~ '^(19|20)[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])([01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]$'
        then ((substr(b.horodatage, 1, 4) || '-' || substr(b.horodatage, 5, 2) || '-01')::timestamp
              + make_interval(days  => substr(b.horodatage, 7, 2)::int - 1,
                              hours => substr(b.horodatage, 9, 2)::int,
                              mins  => substr(b.horodatage, 11, 2)::int,
                              secs  => substr(b.horodatage, 13, 2)::int)) at time zone 'UTC'
    end                                                                     as enrole_le,
    b.synchronise_le,
    b.nb_synchronisations,
    b.refus_poste,
    b.recu_le,
    pg_catalog.date(b.recu_le at time zone 'UTC')                           as jour_reception,
    b.niu_le,
    pg_catalog.date(b.niu_le at time zone 'UTC')                            as jour_niu,
    b.type_lien,
    b.status_code,
    b.etape_code,
    b.etape_statut,
    case
        when b.status_code = 'REJECTED' and b.etape_code = 'VALIDATE_PACKET' and b.refus_poste then 'REFUS_POSTE'
        else b.etape_code
    end                                                                     as etape,
    b.derniere_transaction_le,
    case
        when not b.recu then 'non_recu'
        when b.niu_le is not null then 'niu'
        else coalesce(st.devenir_sans_niu, 'non_classe')
    end                                                                     as devenir,
    coalesce(b.offset_inscription, -1)                                      as offset_inscription,
    coalesce(b.offset_lien, -1)                                             as offset_lien,
    coalesce(b.offset_synchro, -1)                                          as offset_synchro,
    now()                                                                   as maj_le
from base b
left join {{ ref('ref_regprc_statuts') }} st on st.status_code = b.status_code
