{#-
  Source de bi.suivi_dossier (suivi d'un dossier, I11 ; migration V7) : une ligne par RID, jalons, étape et devenir.

  Vue sur dwh.suivi_inscription, lue par scripts/publier-indicateurs.sh, qui ne reprend que les lignes écrites depuis sa
  dernière publication (maj_le) et remplace le RID par son empreinte HMAC (clé SUIVI_HMAC_CLE de compose/.env) : le
  RID n'est jamais écrit dans bi.
  Motif : code du motif de MOSIP (dwh.motif_inscription, status_comment rangé par le catalogue) des dossiers rejetés,
  échoués ou en cours, null sinon ; ses libellés sont publiés à part (ref_motif → bi.ref_motif) pour qu'une correction
  du catalogue s'applique sans republier les dossiers (décision du 29/10/2026).
-#}
{{ config(materialized='view') }}

select
    s.rid,
    s.code_centre,
    s.type_demande,
    s.enrole_le,
    s.synchronise_le,
    s.refus_poste,
    s.recu_le,
    s.niu_le,
    s.devenir,
    s.etape,
    coalesce(e.libelle, s.etape)    as etape_libelle,
    s.etape_statut,
    s.derniere_transaction_le,
    m.motif,
    s.maj_le
from {{ ref('suivi_inscription') }} s
left join {{ ref('ref_regprc_etapes') }} e on e.code = s.etape
left join {{ ref('motif_inscription') }} m on m.rid = s.rid
