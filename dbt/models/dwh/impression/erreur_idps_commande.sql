{#-
  Commandes qui ont eu au moins une erreur d'envoi à l'IDPS (I-ERR, lot 8d) : une ligne par request_id, avec la
  première et la dernière erreur et leur nombre. Une commande en erreur plusieurs fois compte une seule fois, même si
  l'envoi a réussi ensuite.

  Reconstruite à chaque passage depuis le lake (≈ 300 000 événements, quelques secondes) : suivi_carte n'est pas
  modifié (pas de --full-refresh de ses 6,2 M de lignes à la mise en service). Les faits la joignent par request_id.
-#}
{{ config(indexes=[{'columns': ['request_id'], 'unique': True}]) }}

select
    request_id,
    min(erreur_le)                              as premiere_erreur_le,
    max(erreur_le)                              as derniere_erreur_le,
    cast(count(*) as integer)                   as erreurs
from {{ ref('stg_regprc__printing_erreurs_idps') }}
group by request_id
