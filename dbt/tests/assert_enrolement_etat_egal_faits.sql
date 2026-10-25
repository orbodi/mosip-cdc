-- Tout paquet reçu de dwh.suivi_inscription est compté une fois dans fait_enrolement_jour, et suivi_inscription a une
-- ligne par inscription de l'ODS. Renvoie une ligne en cas d'écart.
with ods as (
    select count(*) as n from {{ source('ods', 'regprc_registration') }} where id is not null
),
suivi as (
    select count(*) as n from {{ ref('suivi_inscription') }} where devenir <> 'non_recu'
),
faits as (
    select coalesce(sum(inscriptions), 0) as n from {{ ref('fait_enrolement_jour') }}
)
select ods.n as ods, suivi.n as suivi, faits.n as faits
from ods, suivi, faits
where ods.n <> suivi.n or suivi.n <> faits.n
