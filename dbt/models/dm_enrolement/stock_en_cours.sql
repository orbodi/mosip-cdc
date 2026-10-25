{#-
  Paquets en cours, par étape et ancienneté (I7 ; « dont N bloqués »). Stock à l'heure du passage, pas un fait par
  jour. Futur contrat bi.stock_en_cours (migration V7).

  - anciennete : depuis la dernière transaction (latest_trn_dtimes) : moins_7j, 7_30j, plus_30j. « Bloqués » = plus_30j
    (relevé étape 5 : 96 % de la file de vérification manuelle).
  - Recalculé en entier à chaque passage (≈ 70 000 lignes lues) : l'ancienneté change avec l'heure, même sans
    nouvel événement.
  - Contrôle : total = en_cours de fait_enrolement_jour.
-#}
{{ config(indexes=[{'columns': ['code_centre', 'type_demande', 'etape', 'anciennete'], 'unique': True}]) }}

select
    s.code_centre,
    s.type_demande,
    coalesce(s.etape, 'INCONNUE')                   as etape,
    coalesce(e.libelle, s.etape, 'Étape inconnue')  as etape_libelle,
    coalesce(e.ordre, 999)                          as etape_ordre,
    case
        when s.derniere_transaction_le >= now() - interval '7 days'  then 'moins_7j'
        when s.derniere_transaction_le >= now() - interval '30 days' then '7_30j'
        else 'plus_30j'
    end                                             as anciennete,
    cast(count(*) as integer)                       as inscriptions,
    now()                                           as calcule_le
from {{ ref('suivi_inscription') }} s
left join {{ ref('ref_regprc_etapes') }} e on e.code = s.etape
where s.devenir = 'en_cours'
group by 1, 2, 3, 4, 5, 6
