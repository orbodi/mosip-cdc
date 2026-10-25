-- Chaque ligne de fait_enrolement_jour respecte la contrainte de bi.fait_enrolement_jour (migration V2) :
-- niu_generes + en_cours + echouees + rejetees + non_classees = inscriptions. Renvoie les lignes en écart.
select *
from {{ ref('fait_enrolement_jour') }}
where niu_generes + en_cours + echouees + rejetees + non_classees <> inscriptions
