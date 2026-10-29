{#-
  Source de bi.ref_motif (décision du 29/10/2026) : le catalogue des motifs de MOSIP (seeds/ref_regprc_motifs.csv)
  sans ses règles, pour l'API du suivi d'un dossier, qui joint le motif d'un dossier à son libellé, au message type de
  MOSIP et à sa piste. Remplacé à chaque publication : une correction du catalogue s'applique au passage suivant.
-#}
select
    motif,
    libelle,
    commentaire,
    piste
from {{ ref('ref_regprc_motifs') }}
