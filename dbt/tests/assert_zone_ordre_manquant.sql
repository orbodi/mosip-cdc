{{ config(severity='warn') }}
-- Régions et préfectures sans rang du nord au sud (seeds/ref_zone_ordre.csv) : elles s'affichent en fin de liste dans
-- le tableau de bord. Ajouter leur code au seed (nouvelle zone de master.location). Renvoie les zones concernées.
select code, niveau, nom
from {{ ref('dim_zone') }}
where niveau in ('region', 'prefecture')
  and ordre = 999
