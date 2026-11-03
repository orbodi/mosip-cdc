{#-
  Contrat du backend : bi.stock_niu_sans_commande (migration V16, lot 8d, I-SANS). NIU de première inscription (lien
  rid_uin_link de type NEW) sans aucune commande d'impression (regprc.printing_orders), à l'heure du passage, par
  centre et ancienneté du NIU : moins_7j (commande normalement en route) ou plus_7j (bloqué). Les mises à jour et
  les pertes de NIU ne déclenchent en général pas de carte : elles ne sont pas comptées.

  Stock recalculé à chaque passage (anti-jointure sur le RID, index de l'ODS) ; relevé du 02/11/2026 : 55.
-#}
{{ config(indexes=[{'columns': ['code_centre', 'anciennete'], 'unique': True}]) }}

select
    s.code_centre,
    case when s.niu_le >= now() - interval '7 days' then 'moins_7j' else 'plus_7j' end as anciennete,
    cast(count(*) as integer)                   as niu,
    min(s.niu_le)                               as plus_ancien_le,
    now()                                       as calcule_le
from {{ ref('suivi_inscription') }} s
where s.niu_le is not null
  and s.type_lien = 'NEW'
  and not exists (
      select 1 from {{ ref('stg_regprc__printing_orders') }} o where o.rid = s.rid
  )
group by 1, 2
