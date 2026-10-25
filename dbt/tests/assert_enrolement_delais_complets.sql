-- Les histogrammes de délais comptent tous les paquets concernés : reception_niu = NIU générés ;
-- enrolement_reception = paquets reçus dont le RID porte un horodatage. Renvoie les écarts.
with attendu as (
    select 'reception_niu' as mesure, count(*) filter (where devenir = 'niu') as n
    from {{ ref('suivi_inscription') }}
    union all
    select 'enrolement_reception', count(*) filter (where devenir <> 'non_recu' and enrole_le is not null)
    from {{ ref('suivi_inscription') }}
),
histogrammes as (
    select mesure, sum(paquets) as n from {{ ref('fait_delai_jour') }} group by 1
)
select a.mesure, a.n as attendu, coalesce(h.n, 0) as histogramme
from attendu a
left join histogrammes h using (mesure)
where a.n <> coalesce(h.n, 0)
