{{ config(severity='warn') }}
-- Alerte (non bloquante) : liens dont entry_date a changé après coup dans MOSIP (journal du lake). Si ce nombre
-- grossit, la date du NIU n'est pas stable : à signaler à l'équipe MOSIP (relevé, étape 4).
-- Limité aux liens modifiés ces 7 derniers jours, pour que le contrôle reste rapide quand le journal grossit.
select reg_id
from {{ source('lake', 'mosip_regprc_rid_uin_link') }}
where reg_id in (select reg_id from {{ source('lake', 'mosip_regprc_rid_uin_link') }}
                 where __source_ts_ms >= (extract(epoch from now() - interval '7 days') * 1000)::bigint)
  and entry_date is not null
group by reg_id
having count(distinct entry_date) > 1
