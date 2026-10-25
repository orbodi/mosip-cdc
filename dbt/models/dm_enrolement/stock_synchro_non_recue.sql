{#-
  Paquets synchronisés par le poste mais pas encore reçus par MOSIP (I10). Stock à l'heure du passage. Futur contrat
  bi.stock_synchro_non_recue (migration V7).

  - anciennete : depuis la première synchronisation : moins_7j (probablement en transit) ou plus_7j (probablement
    perdus).
-#}
{{ config(indexes=[{'columns': ['code_centre', 'anciennete'], 'unique': True}]) }}

select
    code_centre,
    case when synchronise_le >= now() - interval '7 days' then 'moins_7j' else 'plus_7j' end   as anciennete,
    cast(count(*) as integer)                                                                   as paquets,
    min(synchronise_le)                                                                         as plus_ancienne_le,
    now()                                                                                       as calcule_le
from {{ ref('suivi_inscription') }}
where devenir = 'non_recu'
group by 1, 2
