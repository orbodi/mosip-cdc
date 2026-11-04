-- Authentifications (contraintes de bi, migration V17) : une échouée a un motif, une réussie ou non classée n'en a pas
-- (AUCUN) ; les demandes de code OTP refusées et les codes utilisés sont des parties de leur total.
-- Renvoie les lignes en écart.
select 'authentification' as fait, jour, appelant_id, type || '/' || statut || '/' || motif as detail
from {{ ref('fait_authentification_jour') }}
where (statut = 'echouee') <> (motif <> 'AUCUN') or authentifications <= 0
union all
select 'demande_otp', jour, appelant_id, demandes || '/' || refusees
from {{ ref('fait_demande_otp_jour') }}
where refusees < 0 or refusees > demandes
union all
select 'code_otp', jour, null, codes || '/' || utilises
from {{ ref('fait_code_otp_jour') }}
where utilises < 0 or utilises > codes
