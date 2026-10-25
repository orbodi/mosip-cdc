{#-
  Contrat du backend : bi.fait_niu_jour (migration V3 de mosip-bi-reporting), lecture « flux » (I2 flux, I3).
  Une ligne par jour de génération du NIU (rid_uin_link.entry_date), centre (code) et type de demande.

  Mêmes paquets que les niu_generes de fait_enrolement_jour, rattachés au jour du NIU et non au jour de réception :
  sur toute la durée, les deux totaux sont égaux (test assert_enrolement_niu_concordent).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande'], 'unique': True}]) }}

select
    jour_niu                                as jour,
    code_centre,
    type_demande,
    cast(count(*) as integer)               as niu_generes
from {{ ref('suivi_inscription') }}
where devenir = 'niu'
group by 1, 2, 3
