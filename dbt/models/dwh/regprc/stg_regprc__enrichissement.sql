{#-
  Dernière réponse de l'ID Repository pour chaque inscription qui a un NIU (job Spark, lot 6), lue dans le lake
  (connecteur lake-regprc-enrichissement) : une ligne par RID. L'ID Repository est appelé avec le RID, jamais avec le
  NIU ; seuls le genre, la nationalité, l'année et le mois de naissance sont gardés.

  - sexe : F (genre « Femme », ou FLE), H (« Homme », ou MLE), I pour tout autre genre ou un genre absent, jamais deviné
    (alerte assert_enrolement_genres_inconnus).
  - nationalite : valeur de l'ID Repository (ex. « TOGO ») ; son libellé est cherché dans la liste MOSIP « nationality »
    par fait_niu_profil_jour.
  - Incrémental par __connect_offset : une partition, l'ordre des offsets est celui des réponses ; seuls les RID qui ont
    une nouvelle réponse sont réécrits.
-#}
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='rid',
    indexes=[
      {'columns': ['rid'], 'unique': True},
      {'columns': ['connect_offset']},
      {'columns': ['enrichi_le']}
    ]
) }}

select distinct on (rid)
    rid,
    nullif(genre, '')                                                       as genre,
    case
        when upper(genre) in ('FEMME', 'FLE') then 'F'
        when upper(genre) in ('HOMME', 'MLE') then 'H'
        else 'I'
    end                                                                     as sexe,
    nullif(nationalite, '')                                                 as nationalite,
    annee_naissance,
    mois_naissance,
    enrichi_le at time zone 'UTC'                                           as enrichi_le,
    __connect_offset                                                        as connect_offset
from {{ source('lake', 'mosip_regprc_enrichissement') }}
where rid is not null
{% if is_incremental() %}
  and __connect_offset > (select coalesce(max(connect_offset), -1) from {{ this }})
{% endif %}
order by rid, __connect_offset desc
