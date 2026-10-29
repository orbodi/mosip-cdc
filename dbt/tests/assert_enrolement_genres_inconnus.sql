{{ config(severity='warn') }}
-- Genres de l'ID Repository que stg_regprc__enrichissement ne reconnaît pas (ni Femme, ni Homme, ni FLE, ni MLE) :
-- les NIU concernés comptent en sexe I, jamais devinés. Alerte, pas un blocage : ajouter la valeur à la règle du
-- modèle. Lit seulement les réponses du dernier jour (index sur enrichi_le). Une ligne par valeur inconnue.
select genre, count(*) as reponses
from {{ ref('stg_regprc__enrichissement') }}
where sexe = 'I'
  and genre is not null
  and enrichi_le >= now() - interval '1 day'
group by genre
