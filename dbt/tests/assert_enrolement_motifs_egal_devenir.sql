-- Bloc « Où s'arrêtent les paquets » par motif : par devenir, la somme des étapes × motifs égale les rejetées, les
-- échouées et les en-cours du Devenir (fait_enrolement_jour). Renvoie les écarts (bloquant).
with motifs as (
    select devenir, sum(inscriptions) as n from {{ ref('fait_arret_motif_jour') }} group by 1
    union all
    select 'en_cours', sum(inscriptions) from {{ ref('stock_en_cours_motif') }}
),
devenir as (
    select 'rejete' as devenir, sum(rejetees) as n from {{ ref('fait_enrolement_jour') }}
    union all
    select 'echoue', sum(echouees) from {{ ref('fait_enrolement_jour') }}
    union all
    select 'en_cours', sum(en_cours) from {{ ref('fait_enrolement_jour') }}
)
select d.devenir, coalesce(d.n, 0) as devenir_n, coalesce(m.n, 0) as motifs_n
from devenir d
left join motifs m using (devenir)
where coalesce(d.n, 0) <> coalesce(m.n, 0)
