{#- Une seule ligne : bornes des données de pré-inscription, publiées dans bi.source_fraicheur
    (premiere_donnee = borne basse du filtre Période du tableau de bord). -#}
select
    pg_catalog.date(min(cree_le) at time zone 'UTC')   as premiere_donnee,
    max(cree_le)                                       as derniere_donnee
from {{ ref('fct_preinscription') }}
