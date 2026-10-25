{#- Une seule ligne : bornes des données d'enrôlement, publiées dans bi.source_fraicheur (premiere_donnee = borne
    basse du filtre Période ; derniere_donnee = dernière réception, qui borne les semaines de la page Enrôlement).
    Vide (valeurs nulles) tant que la capture n'a rien reçu : la publication ne touche alors pas la ligne. -#}
select
    min(jour_reception)    as premiere_donnee,
    max(recu_le)           as derniere_donnee
from {{ ref('suivi_inscription') }}
where devenir <> 'non_recu'
