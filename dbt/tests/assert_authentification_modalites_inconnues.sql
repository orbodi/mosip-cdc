{{ config(severity='warn') }}
-- Codes de modalité (auth_type_code) absents de seeds/ref_ida_modalites.csv, vus au dernier passage : l'authentification
-- compte en type « non classé ». Alerte : ajouter le code et sa famille au seed, puis
-- dbt build --full-refresh --select authentification+.
select s.auth_type_code, count(*) as transactions
from {{ ref('authentification') }} a
join {{ ref('stg_ida__auth_transaction') }} s on s.transaction_id = a.transaction_id
where a.type = 'non_classe'
  and a.maj_le = (select max(maj_le) from {{ ref('authentification') }})
group by 1
