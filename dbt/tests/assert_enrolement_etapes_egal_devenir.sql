-- Bloc « Où s'arrêtent les paquets » : par devenir, la somme des étapes égale les rejetées et les échouées du Devenir
-- (fait_enrolement_jour), et la somme du stock des en-cours égale ses en-cours. Renvoie les écarts.
with etapes as (
    select devenir, sum(inscriptions) as n from {{ ref('fait_arret_etape_jour') }} group by 1
    union all
    select 'en_cours', sum(inscriptions) from {{ ref('stock_en_cours') }}
),
devenir as (
    select 'rejete' as devenir, sum(rejetees) as n from {{ ref('fait_enrolement_jour') }}
    union all
    select 'echoue', sum(echouees) from {{ ref('fait_enrolement_jour') }}
    union all
    select 'en_cours', sum(en_cours) from {{ ref('fait_enrolement_jour') }}
)
select d.devenir, coalesce(d.n, 0) as devenir_n, coalesce(e.n, 0) as etapes_n
from devenir d
left join etapes e using (devenir)
where coalesce(d.n, 0) <> coalesce(e.n, 0)
