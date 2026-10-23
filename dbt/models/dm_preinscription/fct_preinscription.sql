{#-
  Table de faits : une ligne par dossier. Reste sur la BD traitement (non publiée vers l'API).

  - a_ete_reserve : le dossier a eu le statut Booked à un moment connu (même s'il ne l'a plus).
  - reserve_le et delai_reservation_min : renseignés seulement quand le passage à Booked a été
    observé par la capture, donc à l'heure exacte. Vides pour les dossiers déjà réservés au
    snapshot du 21/10/2026, dont l'heure de réservation n'est pas connue.
  - historique_complet : le dossier a été créé après le début de la capture ; tout son
    parcours est connu.
  - sexe : F ou H d'après l'API de pré-inscription ; I tant que le dossier n'est pas enrichi.
  - age_a_la_demande : âge en années révolues au jour de la création, d'après l'année et le mois de naissance
    (mois inconnu : seule l'année compte) ; vide si l'année n'est pas connue.
  - nationalite : libellé de la liste MOSIP « nationality » ; « Non renseignée » sans code connu.
  - prefecture_code : préfecture de résidence déclarée, seulement si elle existe dans dim_zone.
-#}
{{ config(indexes=[
    {'columns': ['prereg_id'], 'unique': True},
    {'columns': ['date_creation_key']}
]) }}

with etat as (

    select * from {{ ref('stg_prereg__applicant_demographic') }}

),

parcours as (

    select
        prereg_id,
        bool_or(status_code = 'Booked')                                       as a_ete_reserve,
        min(valid_from) filter (where status_code = 'Booked' and not date_estimee)
                                                                              as reserve_le,
        bool_and(not date_estimee)                                            as historique_complet,
        count(*)                                                              as nb_changements_statut
    from {{ ref('stg_prereg__applicant_demographic_status_history') }}
    group by prereg_id

)

select
    e.prereg_id,
    cast(to_char(e.created_at at time zone 'UTC', 'YYYYMMDD') as integer)   as date_creation_key,
    e.status_code,
    coalesce(en.sexe, 'I')                                                  as sexe,
    case when en.annee_naissance is not null then
        cast(extract(year from e.created_at at time zone 'UTC') as integer) - en.annee_naissance
        - case when en.mois_naissance > cast(extract(month from e.created_at at time zone 'UTC') as integer)
               then 1 else 0 end
    end                                                                     as age_a_la_demande,
    en.nationalite                                                          as nationalite_code,
    coalesce(nat.libelle, 'Non renseignée')                                 as nationalite,
    zp.code                                                                 as prefecture_code,
    e.lang_code                                                             as langue,
    e.is_deleted                                                            as est_supprime,
    e.created_at                                                            as cree_le,
    e.deleted_at                                                            as supprime_le,
    coalesce(p.a_ete_reserve, false)                                        as a_ete_reserve,
    p.reserve_le,
    round(cast(extract(epoch from (p.reserve_le - e.created_at)) / 60 as numeric), 1)
                                                                            as delai_reservation_min,
    coalesce(p.historique_complet, false)                                   as historique_complet,
    coalesce(p.nb_changements_statut, 0)                                    as nb_changements_statut
from etat e
left join parcours p using (prereg_id)
left join {{ ref('stg_prereg__enrichissement') }} en using (prereg_id)
left join {{ ref('stg_master__dynamic_field_valeurs') }} nat
       on nat.champ = 'nationality' and nat.code = en.nationalite
left join {{ ref('dim_zone') }} zp
       on zp.code = en.prefecture_code and zp.niveau = 'prefecture'
