{{ config(severity='warn') }}
-- Commentaires de MOSIP qu'aucune règle de seeds/ref_regprc_motifs.csv ne reconnaît : comptés en « Motif non répertorié ».
-- Alerte, pas un blocage : ajouter le message (chiffres masqués ci-dessous) et sa traduction au catalogue ; les
-- inscriptions concernées rejoignent leur motif au passage suivant. Une ligne par message inconnu.
select left(regexp_replace(r.commentaire, '[0-9]', '#', 'g'), 160) as commentaire, count(*) as inscriptions
from {{ ref('motif_inscription') }} m
join {{ ref('stg_regprc__registration') }} r on r.rid = m.rid
where m.motif = 'AUTRE'
  and r.commentaire is not null
group by 1
