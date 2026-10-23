{#- Une ligne par statut MOSIP, avec son libellé et son ordre d'affichage (fichier seeds/ref_prereg_statuts.csv). -#}
select
    status_code,
    libelle,
    ordre,
    est_final,
    statut_regroupe   -- statut affiché par le tableau de bord (bi.fait_preinscription_jour) ; vide = non classé
from {{ ref('ref_prereg_statuts') }}
