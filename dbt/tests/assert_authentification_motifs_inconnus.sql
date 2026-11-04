{{ config(severity='warn') }}
-- Messages d'échec d'IDA qu'aucune règle de seeds/ref_ida_motifs.csv ne reconnaît, vus au dernier passage : comptés en
-- « Motif non répertorié ». Alerte : ajouter le message (chiffres masqués ci-dessous) et son libellé au seed, puis
-- dbt build --full-refresh --select authentification+. Une ligne par message inconnu.
select left(regexp_replace(coalesce(s.commentaire, '(vide)'), '[0-9]', '#', 'g'), 160) as message, count(*) as transactions
from {{ ref('authentification') }} a
join {{ ref('stg_ida__auth_transaction') }} s on s.transaction_id = a.transaction_id
where a.motif = 'AUTRE'
  and a.maj_le = (select max(maj_le) from {{ ref('authentification') }})
group by 1
