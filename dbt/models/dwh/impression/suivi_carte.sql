{#-
  Table pivot de l'impression (lot 8) : une ligne par commande d'impression (regprc.printing_orders), avec sa carte
  et sa remise. Tous les faits de dm_impression en sont tirés. Relevé et décisions : docs/releve-impression.md.

  On compte des commandes, jamais des événements (une carte peut être mise en boîte deux fois, une remise enregistrée
  deux fois) : pour chaque jalon, la première date.
  - commande_le : réception de la commande (I-DEM) ; statut : prc_status regroupé par seeds/ref_impression_statuts.csv
    (en_attente = NEW, envoyee = OK, rejetee = KO ; tout autre code = non_classee, jamais deviné) ;
  - envoye_le : envoi à l'imprimeur ; expedie_le : première expédition de la carte (I-EXP) ;
  - remise : la carte a le statut DELIVERED (I-REM) ; remis_le : première date de remise ; mode_remise : delivery_mode
    regroupé par seeds/ref_impression_modes_remise.csv (autre si absent) ; une carte expédiée non remise est à
    remettre (I-AREM), même si elle porte une date de remise (anomalie : date_sans_remise) ;
  - annule_le, motif_annulation : première annulation (NEW-PRINT-CANCELED), comptée à part (décision du 02/11/2026) :
    elle ne retire la commande d'aucun autre total ;
  - niu_le : génération du NIU (rid_uin_link.entry_date), pour le délai du NIU à la carte (I-DELAI).
  - code_centre : cinq premiers chiffres du RID, comme l'enrôlement (lieu de remise = centre d'enrôlement).

  Incrémental : à chaque passage, seules les commandes touchées depuis le passage précédent sont recalculées
  (delete+insert), repérées par l'offset Kafka de chacune des quatre sources (commandes, cartes, annulations, liens
  RID → NIU). maj_le : heure du passage qui a écrit la ligne ; les alertes ne regardent que les lignes du dernier
  passage (index sur maj_le, et sur offset_carte pour assert_impression_cartes_sans_commande).

  Le RID et request_id restent dans le data warehouse ; rien de ce qui identifie une commande n'est publié vers bi.
-#}
{{ config(
    materialized='incremental',
    unlogged=false,
    incremental_strategy='delete+insert',
    unique_key='commande_id',
    indexes=[
      {'columns': ['commande_id'], 'unique': True},
      {'columns': ['maj_le']},
      {'columns': ['offset_carte']}
    ]
) }}

with

{% if is_incremental() %}
reperes as (

    select
        coalesce(max(offset_commande), -1)      as offset_commande,
        coalesce(max(offset_carte), -1)         as offset_carte,
        coalesce(max(offset_annulation), -1)    as offset_annulation,
        coalesce(max(offset_lien), -1)          as offset_lien
    from {{ this }}

),

touchees as (

    select o.commande_id
    from {{ ref('stg_regprc__printing_orders') }} o, reperes p
    where o.kafka_offset > p.offset_commande
    union
    select o.commande_id
    from {{ ref('stg_regprc__printing_shipped_cards') }} c
    cross join reperes p
    join {{ ref('stg_regprc__printing_orders') }} o on o.request_id = c.request_id
    where c.kafka_offset > p.offset_carte
    union
    select o.commande_id
    from {{ ref('stg_regprc__printing_annulations') }} a
    cross join reperes p
    join {{ ref('stg_regprc__printing_orders') }} o on o.request_id = a.request_id
    where a.connect_offset > p.offset_annulation
    union
    select o.commande_id
    from {{ ref('stg_regprc__rid_uin_link') }} l
    cross join reperes p
    join {{ ref('stg_regprc__printing_orders') }} o on o.rid = l.rid
    where l.kafka_offset > p.offset_lien

),

commandes as (

    select o.*
    from {{ ref('stg_regprc__printing_orders') }} o
    join touchees t using (commande_id)

),
{% else %}
commandes as (

    select * from {{ ref('stg_regprc__printing_orders') }}

),
{% endif %}

cartes as (

    select
        c.request_id,
        count(*)                                                    as nb_cartes,
        min(c.expedie_le)                                           as expedie_le,
        bool_or(c.remise)                                           as remise,
        min(c.remis_le) filter (where c.remise)                     as remis_le,
        (array_agg(c.delivery_mode order by c.remis_le nulls last, c.carte_id)
            filter (where c.remise))[1]                             as delivery_mode,
        bool_or(not c.remise and c.remis_le is not null)            as date_sans_remise,
        max(c.kafka_offset)                                         as offset_carte
    from {{ ref('stg_regprc__printing_shipped_cards') }} c
    where c.request_id in (select request_id from commandes)
    group by c.request_id

),

annulations as (

    select
        a.request_id,
        min(a.annule_le)                                            as annule_le,
        (array_agg(a.reason_code order by a.annule_le, a.connect_offset))[1] as reason_code,
        max(a.connect_offset)                                       as offset_annulation
    from {{ ref('stg_regprc__printing_annulations') }} a
    where a.request_id in (select request_id from commandes)
    group by a.request_id

)

select
    k.commande_id,
    k.request_id,
    k.rid,
    left(k.rid, 5)                                                  as code_centre,
    k.prc_status,
    coalesce(st.statut, 'non_classee')                              as statut,
    k.commande_le,
    pg_catalog.date(k.commande_le at time zone 'UTC')               as jour_commande,
    k.envoye_le,
    coalesce(c.nb_cartes, 0)                                        as nb_cartes,
    c.expedie_le,
    pg_catalog.date(c.expedie_le at time zone 'UTC')                as jour_expedition,
    coalesce(c.remise, false)                                       as remise,
    c.remis_le,
    case
        when coalesce(c.remise, false) then coalesce(m.mode, 'autre')
    end                                                             as mode_remise,
    coalesce(c.date_sans_remise, false)                             as date_sans_remise,
    a.annule_le,
    case
        when a.request_id is not null then coalesce(ma.motif, 'NON_REPERTORIE')
    end                                                             as motif_annulation,
    l.niu_le,
    coalesce(k.kafka_offset, -1)                                    as offset_commande,
    coalesce(c.offset_carte, -1)                                    as offset_carte,
    coalesce(a.offset_annulation, -1)                               as offset_annulation,
    coalesce(l.kafka_offset, -1)                                    as offset_lien,
    now()                                                           as maj_le
from commandes k
left join cartes c on c.request_id = k.request_id
left join annulations a on a.request_id = k.request_id
left join {{ ref('stg_regprc__rid_uin_link') }} l on l.rid = k.rid
left join {{ ref('ref_impression_statuts') }} st on st.prc_status = k.prc_status
left join {{ ref('ref_impression_modes_remise') }} m on m.delivery_mode = c.delivery_mode
left join {{ ref('ref_impression_motifs_annulation') }} ma on ma.reason_code = a.reason_code
