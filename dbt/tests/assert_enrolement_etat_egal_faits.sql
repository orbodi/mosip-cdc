-- Complétude de la chaîne de l'enrôlement. Renvoie une ligne en cas d'écart.
-- 1. Chaque inscription de l'ODS déjà lue par dbt (offset inférieur ou égal au dernier offset traité) figure dans
--    dwh.suivi_inscription. On ne compte pas l'ODS entier : le connecteur continue d'écrire pendant le passage, et une
--    inscription arrivée après la construction du suivi n'est pas une erreur (incident du 25/10/2026, 16 h 50).
-- 2. Chaque paquet reçu du suivi existe dans l'ODS (aucune suppression dans MOSIP).
-- 3. Chaque paquet reçu du suivi est compté une fois dans fait_enrolement_jour (même passage dbt).
with repere as (
    select coalesce(max(offset_inscription), -1) as offset_traite from {{ ref('suivi_inscription') }}
),
manquantes as (
    select count(*) as n
    from {{ source('ods', 'regprc_registration') }} r, repere p
    where r.id is not null
      and r.__kafka_offset <= p.offset_traite
      and not exists (select 1 from {{ ref('suivi_inscription') }} s where s.rid = r.id)
),
orphelines as (
    select count(*) as n
    from {{ ref('suivi_inscription') }} s
    where s.devenir <> 'non_recu'
      and not exists (select 1 from {{ source('ods', 'regprc_registration') }} r where r.id = s.rid)
),
suivi as (
    select count(*) as n from {{ ref('suivi_inscription') }} where devenir <> 'non_recu'
),
faits as (
    select coalesce(sum(inscriptions), 0) as n from {{ ref('fait_enrolement_jour') }}
)
select manquantes.n as ods_absentes_du_suivi, orphelines.n as suivi_absentes_de_l_ods, suivi.n as suivi, faits.n as faits
from manquantes, orphelines, suivi, faits
where manquantes.n > 0 or orphelines.n > 0 or suivi.n <> faits.n
