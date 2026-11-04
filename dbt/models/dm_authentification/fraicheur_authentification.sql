{#- Une seule ligne : bornes des données d'authentification, publiées dans bi.source_fraicheur (source
    « authentifications »). premiere_donnee : premier jour (borne basse du filtre Période) ; derniere_donnee :
    authentification ou code OTP le plus récent. Vide (valeurs nulles) tant que la capture n'a rien reçu : la
    publication ne touche alors pas la ligne. -#}
select
    min(a.jour)                                                         as premiere_donnee,
    greatest(max(a.authentifie_le), (select max(o.demande_le) from {{ ref('stg_ida__otp_transaction') }} o)) as derniere_donnee
from {{ ref('authentification') }} a
where not a.supprime
