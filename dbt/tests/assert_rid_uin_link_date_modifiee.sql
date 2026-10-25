{{ config(severity='warn') }}
-- Alerte (non bloquante) : liens dont entry_date a changé après coup dans MOSIP (journal du lake). Si ce nombre
-- grossit, la date du NIU n'est pas stable : à signaler à l'équipe MOSIP (relevé, étape 4).
-- Seuls les liens MODIFIÉS (__op = 'u') ces 7 derniers jours sont relus : les lignes du snapshot (r) et les créations
-- (c) ne sont pas des modifications. Index partiel lake.mosip_regprc_rid_uin_link_modif_idx
-- (sql/traitement/18_index_lake_regprc.sql) : quelques milliers de lignes lues au lieu du journal entier
-- (79 s le 25/10/2026, quand les 6 M de lignes du snapshot dataient toutes de moins de 7 jours).
with modifies as (

    select distinct reg_id
    from {{ source('lake', 'mosip_regprc_rid_uin_link') }}
    where __op = 'u'
      and __source_ts_ms >= (extract(epoch from now() - interval '7 days') * 1000)::bigint

)

select l.reg_id
from modifies m
join {{ source('lake', 'mosip_regprc_rid_uin_link') }} l on l.reg_id = m.reg_id
where l.entry_date is not null
group by l.reg_id
having count(distinct l.entry_date) > 1
