{#-
  Contrat du backend : bi.fait_preinscription_jour (migration V4 de mosip-bi-reporting).
  Une ligne par jour de création (UTC = heure de Lomé), statut regroupé et sexe (F, H, I = inconnu).

  - Tous les dossiers créés comptent une fois, y compris ceux supprimés depuis de MOSIP
    (consommés au centre ou abandonnés), avec leur dernier statut connu : le total des
    demandes d'une période ne baisse pas.
  - statut : correspondance de seeds/ref_prereg_statuts.csv ; sans correspondance = non_classe.
  - consommees = 0 : la table applicant_demographic_consumed n'est pas capturée (décision du 23/10/2026).
-#}
{{ config(indexes=[{'columns': ['jour', 'statut', 'sexe'], 'unique': True}]) }}

select
    pg_catalog.date(f.cree_le at time zone 'UTC')   as jour,
    coalesce(s.statut_regroupe, 'non_classe')       as statut,
    f.sexe,
    cast(count(*) as integer)                       as demandes,
    0                                               as consommees
from {{ ref('fct_preinscription') }} f
left join {{ ref('dim_statut') }} s using (status_code)
group by 1, 2, 3
