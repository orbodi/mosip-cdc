-- Relevé de l'enrôlement sur mosip_master : référentiel des centres, des machines et des statuts. Lecture seule ;
-- ni adresse, ni contact, ni adresse MAC, ni numéro de série. Réponse R4 de docs/analyse-enrolement.md (à comparer
-- aux préfixes de RID de 03_releve_enrolement_regprc.sql) :
--   psql -h <serveur MOSIP> -U <dba> -d mosip_master -X -A -F ';' -f sql/mosip/03_releve_enrolement_master.sql \
--        -o releve_master.txt
\set ON_ERROR_STOP on
\pset footer off

\qecho '##### Centres : langues et volumes'
SELECT lang_code, count(*) AS lignes, count(DISTINCT id) AS centres,
       count(*) FILTER (WHERE is_active) AS actifs
FROM master.registration_center GROUP BY 1 ORDER BY 1;
SELECT length(id) AS longueur_id, count(DISTINCT id) AS centres FROM master.registration_center GROUP BY 1;
\qecho '-- liste des centres (identifiant, lieu de rattachement, postes, type, actif)'
SELECT DISTINCT ON (id) id, location_code, number_of_kiosks, cntrtyp_code, is_active, coalesce(is_deleted, false) AS supprime
FROM master.registration_center
ORDER BY id, (lang_code = 'fra') DESC, lang_code;

\qecho '##### Machines (identifiant et centre seulement)'
SELECT count(DISTINCT id) AS machines, count(DISTINCT regcntr_id) AS centres_avec_machine,
       count(DISTINCT id) FILTER (WHERE is_active) AS actives
FROM master.machine_master;
SELECT length(id) AS longueur_id, count(DISTINCT id) AS machines FROM master.machine_master GROUP BY 1;
SELECT DISTINCT ON (id) id, regcntr_id, is_active
FROM master.machine_master ORDER BY id, (lang_code = 'fra') DESC, lang_code;

\qecho '##### Hiérarchie des lieux'
SELECT hierarchy_level, hierarchy_level_name, lang_code, count(*) AS lieux
FROM master.location GROUP BY 1, 2, 3 ORDER BY 1, 3;

\qecho '##### Statuts déclarés dans le référentiel (libellés)'
SELECT sttyp_code, code, lang_code, descr, status_seq, is_active
FROM master.status_list ORDER BY sttyp_code, status_seq, code, lang_code;
