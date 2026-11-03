{{ config(severity='warn') }}
-- Anomalies connues de l'impression (relevé du 02/11/2026), à signaler, jamais corrigées : carte expédiée dont la
-- commande est encore NEW (916 au relevé), carte non remise qui porte une date de remise (809, mode SUPPORT).
-- Seulement les commandes écrites au dernier passage (maj_le) : après un --full-refresh, toutes ; ensuite, les
-- nouvelles. Renvoie une ligne par anomalie et par commande, sans identifiant.
select 'carte expédiée, commande en attente' as anomalie, code_centre
from {{ ref('suivi_carte') }}
where maj_le = (select max(maj_le) from {{ ref('suivi_carte') }})
  and statut = 'en_attente' and expedie_le is not null
union all
select 'date de remise sans remise', code_centre
from {{ ref('suivi_carte') }}
where maj_le = (select max(maj_le) from {{ ref('suivi_carte') }})
  and date_sans_remise
union all
select 'plusieurs cartes pour une commande', code_centre
from {{ ref('suivi_carte') }}
where maj_le = (select max(maj_le) from {{ ref('suivi_carte') }})
  and nb_cartes > 1
