{#-
  Motif de chaque inscription qui peut en avoir un (rejetée, échouée, en cours : status_code autre que PROCESSED), tiré
  du status_comment de MOSIP (bloc « Où s'arrêtent les paquets », décision du 26/10/2026).

  - stage : étape de traitement (reg_stage_name) ; INCONNUE si MOSIP n'en donne pas.
  - motif : code de seeds/ref_regprc_motifs.csv. Chaque commentaire distinct est comparé aux règles (expressions
    régulières, sans distinction de casse) ; la règle de plus petite priorité gagne. Un commentaire qu'aucune règle ne
    reconnaît, ou absent, donne AUTRE (« Motif non répertorié ») : jamais deviné, compté, et signalé par le test
    assert_enrolement_motifs_inconnus (alerte) pour compléter le catalogue.
  - Le texte du commentaire ne sort pas de cette étape : seul le code du motif va vers dm_enrolement, puis bi.
  - Table recalculée en entier à chaque passage (≈ 350 000 lignes, quelques centaines de commentaires distincts) : un
    commentaire mis à jour dans l'ODS hors Kafka (scripts/rattraper-status-comment.sh) ou une règle ajoutée au
    catalogue est pris en compte au passage suivant, sans --full-refresh.
-#}
{{ config(materialized='table', indexes=[{'columns': ['rid'], 'unique': True}]) }}

with

inscriptions as (

    select rid, reg_stage_name, commentaire
    from {{ ref('stg_regprc__registration') }}
    where status_code is distinct from 'PROCESSED'
      and not supprime

),

commentaires as (

    select distinct commentaire from inscriptions where commentaire is not null

),

correspondances as (

    select
        c.commentaire,
        (select m.motif
         from {{ ref('ref_regprc_motifs') }} m
         where m.regle is not null and c.commentaire ~* m.regle
         order by m.priorite
         limit 1)                                   as motif
    from commentaires c

)

select
    i.rid,
    coalesce(i.reg_stage_name, 'INCONNUE')          as stage,
    coalesce(k.motif, 'AUTRE')                      as motif
from inscriptions i
left join correspondances k on k.commentaire = i.commentaire
