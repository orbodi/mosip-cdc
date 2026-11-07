{#-
  Contrat du backend : bi.fait_enrolement_jour (migrations V1, V2 et V18 de mosip-bi-reporting).
  Une ligne par jour de réception, centre (code), type de demande, sexe, tranche d'âge et nationalité ; lecture
  « cohorte » : les paquets reçus ce jour-là, dans leur devenir d'aujourd'hui (I1, I2 cohorte, I4).

  - jour : réception par MOSIP (cr_dtimes, UTC = heure de Lomé).
  - code_centre : résolu en centre de bi.zone à la publication (« Centre non référencé » s'il est inconnu).
  - Profil (lot E2 de l'Exploration, 07/11/2026) : sexe, âge et nationalité de l'ID Repository
    (stg_regprc__enrichissement), connus seulement pour les dossiers dont le NIU est généré et enrichi. Les autres
    comptent en sexe I, âge « inconnu », nationalité « Non renseignée » ; un NIU rejoint son profil au passage qui
    suit la réponse de l'ID Repository. Mêmes règles que fait_niu_profil_jour, sauf l'âge : années révolues au jour
    de réception (et non au jour du NIU), d'après l'année et le mois de naissance (mois inconnu : seule l'année
    compte). Les totaux par jour, centre et type sont inchangés.
  - devenir : règle I4 de dwh.suivi_inscription. Contrôle :
    niu_generes + en_cours + echouees + rejetees + non_classees = inscriptions.
  - Paquets synchronisés mais pas encore reçus : exclus (ils n'ont pas de jour de réception ; voir
    stock_synchro_non_recue).
  - en_reprocessing (migration V13, 31/10/2026) : dont en cours dont la dernière transaction MOSIP est REPROCESS
    (etape_statut = latest_trn_status_code) ; MOSIP les reprendra. Partie de en_cours, jamais un statut de plus :
    en_reprocessing ≤ en_cours (contrainte de bi, test assert_enrolement_reprocessing_parmi_en_cours). Un dossier
    échoué, rejeté ou non classé dont la dernière transaction est REPROCESS n'y compte pas (décision du 31/10/2026).
-#}
{{ config(indexes=[{'columns': ['jour', 'code_centre', 'type_demande', 'sexe', 'tranche_age', 'nationalite'],
                   'unique': True}]) }}

with paquets as (

    select
        s.jour_reception                                                    as jour,
        s.code_centre,
        s.type_demande,
        s.devenir,
        s.etape_statut,
        coalesce(e.sexe, 'I')                                               as sexe,
        case when e.annee_naissance is not null then
            cast(extract(year from s.jour_reception) as integer) - e.annee_naissance
            - case when e.mois_naissance > cast(extract(month from s.jour_reception) as integer)
                   then 1 else 0 end
        end                                                                 as age,
        case when e.nationalite is null then 'Non renseignée'
             else coalesce(nat.libelle, e.nationalite) end                  as nationalite
    from {{ ref('suivi_inscription') }} s
    left join {{ ref('stg_regprc__enrichissement') }} e on e.rid = s.rid
    left join {{ ref('stg_master__dynamic_field_valeurs') }} nat
           on nat.champ = 'nationality' and nat.code = e.nationalite
    where s.devenir <> 'non_recu'

)

select
    jour,
    code_centre,
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
    end                                                                 as tranche_age,
    type_demande,
    nationalite,
    cast(count(*) as integer)                                           as inscriptions,
    cast(count(*) filter (where devenir = 'niu') as integer)            as niu_generes,
    cast(count(*) filter (where devenir = 'en_cours') as integer)       as en_cours,
    cast(count(*) filter (where devenir = 'echoue') as integer)         as echouees,
    cast(count(*) filter (where devenir = 'rejete') as integer)         as rejetees,
    cast(count(*) filter (where devenir = 'non_classe') as integer)     as non_classees,
    cast(count(*) filter (where devenir = 'en_cours' and etape_statut = 'REPROCESS') as integer)
                                                                        as en_reprocessing
from paquets
group by 1, 2, 3, 4, 5, 6
