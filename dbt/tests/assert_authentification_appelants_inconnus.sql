{{ config(severity='warn') }}
-- Appelants internes (INTERNAL) absents de seeds/ref_ida_appelants.csv, vus au dernier passage : comptés en
-- « non classé », ni chez les usagers ni dans le traitement des paquets. Alerte : ajouter l'appelant au seed (périmètre,
-- canal, libellé), puis dbt build --full-refresh --select authentification+. Les partenaires (PARTNER) se rangent seuls.
select a.appelant_id, a.appelant, count(*) as transactions
from {{ ref('authentification') }} a
where a.perimetre = 'non_classe'
  and a.maj_le = (select max(maj_le) from {{ ref('authentification') }})
group by 1, 2
