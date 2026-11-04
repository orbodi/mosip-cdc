{#- Contrat du backend : bi.ref_motif_authentification (migration V17). Libellé français de chaque motif d'échec
    (seeds/ref_ida_motifs.csv), plus AUTRE ; AUCUN (réussie) n'a pas de libellé. -#}
select motif, libelle, priorite as ordre from {{ ref('ref_ida_motifs') }}
union all
select 'AUTRE', 'Motif non répertorié', 999
