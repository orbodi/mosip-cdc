{#- Une ligne par statut MOSIP, avec son libellé et son ordre d'affichage (fichier seeds/ref_prereg_statuts.csv). -#}
select
    status_code,
    libelle,
    ordre,
    est_final
from {{ ref('ref_prereg_statuts') }}
