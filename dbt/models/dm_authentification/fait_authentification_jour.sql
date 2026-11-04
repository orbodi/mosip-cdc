{#-
  Contrat du backend : bi.fait_authentification_jour (migration V17, lot 9). Authentifications par jour
  d'enregistrement (cr_dtimes), appelant, type, statut et motif, hors demandes de code OTP (fait_demande_otp_jour).

  - perimetre : usagers (partenaires, portail du résident, USSD) ou paquets (vérifications du traitement des
    paquets) : jamais additionnés (option A, 03/11/2026) ; non_classe pour un appelant interne inconnu.
  - motif : AUCUN pour une réussie, code de seeds/ref_ida_motifs.csv ou AUTRE pour une échouée (contrainte de bi et
    test assert_authentification_statuts_motifs).
  - appelant : nom d'organisation ou de service déclaré dans MOSIP (un seul par appelant et par jour en pratique ;
    l'API affiche celui du jour le plus récent).
-#}
{{ config(indexes=[{'columns': ['jour', 'appelant_id', 'type', 'statut', 'motif'], 'unique': True}]) }}

select
    a.jour,
    min(a.perimetre)                                                    as perimetre,
    min(a.canal)                                                        as canal,
    a.appelant_id,
    min(a.appelant)                                                     as appelant,
    a.type,
    a.statut,
    a.motif,
    cast(count(*) as integer)                                           as authentifications
from {{ ref('authentification') }} a
where not a.supprime
  and not a.demande_otp
group by a.jour, a.appelant_id, a.type, a.statut, a.motif
