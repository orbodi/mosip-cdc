{#-
  Indicateurs publiés vers l'API : une ligne par jour de création et par langue.
  Chiffres de cohorte : les dossiers créés ce jour-là, et ce qu'ils sont devenus depuis.
  Les délais ne portent que sur les réservations observées (voir fct_preinscription).
-#}
{{ config(indexes=[{'columns': ['date_jour', 'langue'], 'unique': True}]) }}

select
    d.date_jour,
    f.langue,
    count(*)                                                              as nb_crees,
    count(*) filter (where f.a_ete_reserve)                               as nb_reserves,
    count(*) filter (where f.status_code = 'Pending_Appointment'
                       and not f.est_supprime)                            as nb_en_attente,
    count(*) filter (where f.est_supprime)                                as nb_supprimes,
    count(f.delai_reservation_min)                                        as nb_delais_mesures,
    round(cast(avg(f.delai_reservation_min) as numeric), 1)               as delai_reservation_moyen_min,
    round(cast(percentile_cont(0.5) within group (order by f.delai_reservation_min) as numeric), 1)
                                                                          as delai_reservation_median_min,
    now()                                                                 as calcule_le
from {{ ref('fct_preinscription') }} f
join {{ ref('dim_date') }} d on d.date_key = f.date_creation_key
group by d.date_jour, f.langue
