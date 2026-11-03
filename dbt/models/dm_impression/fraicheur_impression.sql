{#- Une seule ligne : bornes des données d'impression, publiées dans bi.source_fraicheur (source « cartes »).
    premiere_donnee : premier jour de commande (borne basse du filtre Période) ; derniere_donnee : événement le plus
    récent (commande, envoi, expédition ou remise), qui borne les semaines de la page. Vide (valeurs nulles) tant que
    la capture n'a rien reçu : la publication ne touche alors pas la ligne. -#}
select
    min(jour_commande)                                                  as premiere_donnee,
    greatest(max(commande_le), max(envoye_le), max(expedie_le), max(remis_le)) as derniere_donnee
from {{ ref('suivi_carte') }}
