{#-
  Contrat du backend : bi.fait_code_otp_jour (migration V17, lot 9). Codes OTP de ida.otp_transaction par jour de
  demande (cr_dtimes) : codes, dont utilises (status_code used) ; les autres (active) n'ont jamais servi et ont
  expiré. otp_transaction ne dit pas quel appelant a demandé le code : total de tous les appelants.
-#}
{{ config(indexes=[{'columns': ['jour'], 'unique': True}]) }}

select
    pg_catalog.date(o.demande_le at time zone 'UTC')                    as jour,
    cast(count(*) as integer)                                           as codes,
    cast(count(*) filter (where o.status_code = 'used') as integer)     as utilises
from {{ ref('stg_ida__otp_transaction') }} o
where not o.supprime
  and o.demande_le is not null
group by 1
