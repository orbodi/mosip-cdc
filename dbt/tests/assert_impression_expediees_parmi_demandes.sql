-- Aucune carte sans commande (relevé du 02/11/2026) : par centre, depuis le début, les cartes expédiées ne dépassent
-- pas les demandes d'impression. Les deux faits n'ont pas le même jour (réception de la commande, expédition) : la
-- comparaison se fait sur toute la durée. Renvoie les centres en écart.
with demandes as (
    select code_centre, sum(demandes) as demandes
    from {{ ref('fait_demande_impression_jour') }}
    group by 1
),
cartes as (
    select code_centre, sum(expediees) as expediees
    from {{ ref('fait_carte_jour') }}
    group by 1
)
select c.code_centre, coalesce(d.demandes, 0) as demandes, c.expediees
from cartes c
left join demandes d using (code_centre)
where c.expediees > coalesce(d.demandes, 0)
