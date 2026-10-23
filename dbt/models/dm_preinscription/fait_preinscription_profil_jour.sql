{#-
  Contrat du backend : bi.fait_preinscription_profil_jour (migration V6 de mosip-bi-reporting).
  Une ligne par jour de création, sexe, tranche d'âge (au jour de la demande) et nationalité.
  Mêmes dossiers que fait_preinscription_jour : la somme des demandes est identique.
-#}
{{ config(indexes=[{'columns': ['jour', 'sexe', 'tranche_age', 'nationalite'], 'unique': True}]) }}

with dossiers as (

    select
        pg_catalog.date(cree_le at time zone 'UTC')     as jour,
        sexe,
        case
            when age_a_la_demande is null
              or age_a_la_demande < 0
              or age_a_la_demande > 120 then 'inconnu'
            when age_a_la_demande <= 5   then '0-5'
            when age_a_la_demande <= 14  then '6-14'
            when age_a_la_demande <= 18  then '15-18'
            when age_a_la_demande <= 25  then '19-25'
            when age_a_la_demande <= 35  then '26-35'
            when age_a_la_demande <= 45  then '36-45'
            when age_a_la_demande <= 60  then '46-60'
            else '60+'
        end                                             as tranche_age,
        nationalite
    from {{ ref('fct_preinscription') }}

)

select
    jour,
    sexe,
    tranche_age,
    nationalite,
    cast(count(*) as integer)   as demandes
from dossiers
group by 1, 2, 3, 4
