{#-
  Profil des NIU générés (lot 6) : une ligne par jour de génération du NIU, région du centre, sexe, tranche d'âge (au
  jour du NIU) et nationalité. Source des contrats bi.fait_niu_profil_jour (sans la nationalité) et
  bi.fait_niu_nationalite_jour (sans le sexe ni l'âge), regroupés à la publication.

  - Mêmes NIU que fait_niu_jour (devenir = niu), au même jour : la somme des NIU est identique, jour par jour (test
    assert_enrolement_profil_niu_egal_niu). Un NIU pas encore enrichi compte en sexe I, âge « inconnu », nationalité
    « Non renseignée » : il rejoint son profil au passage qui suit la réponse de l'ID Repository.
  - Région : celle du centre (dim_centre_region), comme le filtre Région des autres blocs ; vide si le centre n'est pas
    rattaché à une région (« Hors référentiel » à la publication).
  - Âge : années révolues au jour du NIU, d'après l'année et le mois de naissance (mois inconnu : seule l'année
    compte) ; tranches de la pyramide des pré-inscriptions.
  - Nationalité : libellé de la liste MOSIP « nationality » si la valeur y est un code, sinon la valeur de l'ID
    Repository telle quelle ; « Non renseignée » sans valeur.
-#}
{{ config(indexes=[{'columns': ['jour', 'code_region', 'sexe', 'tranche_age', 'nationalite']}]) }}

with niu as (

    select
        s.jour_niu                                                          as jour,
        cr.code_region,
        coalesce(e.sexe, 'I')                                               as sexe,
        case when e.annee_naissance is not null then
            cast(extract(year from s.niu_le at time zone 'UTC') as integer) - e.annee_naissance
            - case when e.mois_naissance > cast(extract(month from s.niu_le at time zone 'UTC') as integer)
                   then 1 else 0 end
        end                                                                 as age,
        case when e.nationalite is null then 'Non renseignée'
             else coalesce(nat.libelle, e.nationalite) end                  as nationalite
    from {{ ref('suivi_inscription') }} s
    left join {{ ref('stg_regprc__enrichissement') }} e on e.rid = s.rid
    left join {{ ref('dim_centre_region') }} cr on cr.code_centre = s.code_centre
    left join {{ ref('stg_master__dynamic_field_valeurs') }} nat
           on nat.champ = 'nationality' and nat.code = e.nationalite
    where s.devenir = 'niu'

)

select
    jour,
    code_region,
    sexe,
    case
        when age is null or age < 0 or age > 120 then 'inconnu'
        when age <= 5   then '0-5'
        when age <= 14  then '6-14'
        when age <= 18  then '15-18'
        when age <= 25  then '19-25'
        when age <= 35  then '26-35'
        when age <= 45  then '36-45'
        when age <= 60  then '46-60'
        else '60+'
    end                                                                     as tranche_age,
    nationalite,
    cast(count(*) as integer)                                               as niu_generes
from niu
group by 1, 2, 3, 4, 5
