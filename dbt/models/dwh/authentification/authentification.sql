{#-
  Table pivot des authentifications (lot 9) : une ligne par transaction de ida.auth_transaction, classée. Tous les
  faits de dm_authentification en sont tirés. Relevé et décisions : docs/releve-authentification.md.

  - perimetre, canal, appelant : par seeds/ref_ida_appelants.csv (traitement des paquets, portail du résident, USSD) ;
    un appelant PARTNER absent du seed est un partenaire, sous son nom déclaré dans MOSIP (un nouveau partenaire
    apparaît sans changer le seed) ; un appelant INTERNAL inconnu est non_classe (alerte
    assert_authentification_appelants_inconnus). Usagers et traitement des paquets ne s'additionnent jamais
    (option A, 03/11/2026).
  - demande_otp : la liste contient OTP-REQUEST, demande d'envoi d'un code, pas une authentification (comptée à part).
  - type : famille des modalités de la liste (seeds/ref_ida_modalites.csv) : biometrique (empreinte, iris, visage,
    même plusieurs), otp, demographique ; combinee si plusieurs familles ; sans_mode si aucune (KYC-AUTH seul :
    usage, pas une modalité) ; non_classe si un code est inconnu (alerte assert_authentification_modalites_inconnues).
  - statut : reussie (Y), echouee (N), non_classe (autre code).
  - motif : pour une échouée, code de seeds/ref_ida_motifs.csv (expressions régulières sans distinction de casse sur
    le message, la plus petite priorité gagne) ; AUTRE (« Motif non répertorié ») si aucune règle ne reconnaît le
    message (alerte assert_authentification_motifs_inconnus) ; AUCUN pour une réussie ou non classée. Le message
    lui-même ne sort pas de cette étape.

  Incrémental : à chaque passage, seules les transactions écrites dans l'ODS depuis le passage précédent
  (__kafka_offset) sont classées. Un seed modifié (appelants, modalités, motifs) ne reclasse que les nouvelles :
  dbt build --full-refresh --select authentification+ (quelques minutes, 3,25 M de lignes au 04/11/2026). maj_le :
  heure du passage qui a écrit la ligne ; les alertes ne regardent que le dernier passage.
-#}
{{ config(
    materialized='incremental',
    unlogged=false,
    incremental_strategy='delete+insert',
    unique_key='transaction_id',
    indexes=[
      {'columns': ['transaction_id'], 'unique': True},
      {'columns': ['maj_le']},
      {'columns': ['kafka_offset']}
    ]
) }}

with

nouvelles as (

    select t.*
    from {{ ref('stg_ida__auth_transaction') }} t
    {% if is_incremental() %}
    where t.kafka_offset > (select coalesce(max(kafka_offset), -1) from {{ this }})
    {% endif %}

),

modalites as (

    select n.transaction_id, m.famille
    from nouvelles n
    left join lateral unnest(string_to_array(n.auth_type_code, ',')) as l (code) on true
    left join {{ ref('ref_ida_modalites') }} m on m.code = trim(l.code)

),

types as (

    select
        transaction_id,
        bool_or(famille = 'demande_otp')                                                    as demande_otp,
        bool_or(famille is null)                                                            as inconnue,
        count(distinct famille) filter (where famille in ('biometrique', 'otp', 'demographique')) as familles,
        min(famille) filter (where famille in ('biometrique', 'otp', 'demographique'))      as famille
    from modalites
    group by 1

),

messages as (

    select distinct commentaire from nouvelles where status_code = 'N' and commentaire is not null

),

correspondances as (

    select
        c.commentaire,
        (select m.motif
         from {{ ref('ref_ida_motifs') }} m
         where m.regle is not null and c.commentaire ~* m.regle
         order by m.priorite
         limit 1)                                   as motif
    from messages c

)

select
    n.transaction_id,
    pg_catalog.date(n.authentifie_le at time zone 'UTC')                                as jour,
    n.authentifie_le,
    coalesce(a.perimetre, case when n.type_appelant = 'PARTNER' then 'usagers' else 'non_classe' end) as perimetre,
    coalesce(a.canal, case when n.type_appelant = 'PARTNER' then 'partenaire' else 'non_classe' end)  as canal,
    coalesce(n.appelant_id, 'INCONNU')                                                  as appelant_id,
    coalesce(a.appelant, n.appelant_nom, n.appelant_id, 'Appelant inconnu')            as appelant,
    case
        when t.inconnue then 'non_classe'
        when t.familles = 0 then 'sans_mode'
        when t.familles > 1 then 'combinee'
        else t.famille
    end                                                                                 as type,
    coalesce(t.demande_otp, false)                                                      as demande_otp,
    case n.status_code when 'Y' then 'reussie' when 'N' then 'echouee' else 'non_classe' end as statut,
    case when n.status_code = 'N' then coalesce(k.motif, 'AUTRE') else 'AUCUN' end      as motif,
    n.supprime,
    n.kafka_offset,
    now()                                                                               as maj_le
from nouvelles n
join types t on t.transaction_id = n.transaction_id
left join {{ ref('ref_ida_appelants') }} a on a.requested_entity_id = n.appelant_id
left join correspondances k on k.commentaire = n.commentaire
