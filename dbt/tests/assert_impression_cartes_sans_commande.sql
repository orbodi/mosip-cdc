{{ config(severity='warn') }}
-- Cartes sans commande (aucune au relevé du 02/11/2026) : suivi_carte part des commandes, une carte dont la commande
-- est absente n'est comptée nulle part. Ne regarde que les cartes reçues depuis la plus récente carte rattachée
-- (index sur l'offset de l'ODS), pour ne pas relire 6 M de cartes à chaque passage : une carte orpheline plus
-- ancienne que la dernière carte rattachée n'est pas vue (vérification complète : requête 6 de docs/impression.md).
select c.carte_id
from {{ ref('stg_regprc__printing_shipped_cards') }} c
where c.kafka_offset > (select coalesce(max(offset_carte), -1) from {{ ref('suivi_carte') }} where offset_carte >= 0)
  and not exists (select 1 from {{ ref('stg_regprc__printing_orders') }} o where o.request_id = c.request_id)
