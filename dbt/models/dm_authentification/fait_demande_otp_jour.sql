{#-
  Contrat du backend : bi.fait_demande_otp_jour (migration V17, lot 9). Demandes d'envoi d'un code OTP (OTP-REQUEST :
  pas une authentification, comptée à part) par jour et appelant ; refusees : statut N (IDA n'a pas envoyé le code ;
  relevé : surtout un type d'identifiant non configuré).
-#}
{{ config(indexes=[{'columns': ['jour', 'appelant_id'], 'unique': True}]) }}

select
    a.jour,
    min(a.perimetre)                                                    as perimetre,
    min(a.canal)                                                        as canal,
    a.appelant_id,
    min(a.appelant)                                                     as appelant,
    cast(count(*) as integer)                                           as demandes,
    cast(count(*) filter (where a.statut = 'echouee') as integer)       as refusees
from {{ ref('authentification') }} a
where not a.supprime
  and a.demande_otp
group by a.jour, a.appelant_id
