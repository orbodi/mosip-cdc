-- Relevé de l'enrôlement sur mosip_idrepo : la table idrepo.anonymous_profile existe-t-elle (MOSIP 1.1.5.5 et
-- plus) et que contient-elle ? Comptages seulement : noms de clés du JSON, valeurs de processus et de genre, part des
-- profils avec année de naissance et lieu. Aucun profil n'est affiché. Réponse R10 de docs/analyse-enrolement.md :
--   psql -h <serveur MOSIP> -U <dba> -d mosip_idrepo -X -A -F ';' -f sql/mosip/03_releve_enrolement_idrepo.sql \
--        -o releve_idrepo.txt
\set ON_ERROR_STOP on
\pset footer off

\qecho '##### R10. Table anonymous_profile'
SELECT to_regclass('idrepo.anonymous_profile') IS NOT NULL AS existe \gset
\if :existe
SELECT count(*) AS profils, min(cr_dtimes) AS premier, max(cr_dtimes) AS dernier,
       count(*) FILTER (WHERE coalesce(is_deleted, false)) AS supprimes
FROM idrepo.anonymous_profile;
SELECT to_char(cr_dtimes, 'YYYY-MM') AS mois, count(*) AS profils
FROM idrepo.anonymous_profile GROUP BY 1 ORDER BY 1;
\qecho '-- clés du premier niveau du JSON'
SELECT k AS cle, count(*) AS profils
FROM idrepo.anonymous_profile, jsonb_object_keys(cast(profile AS jsonb)) AS k
GROUP BY 1 ORDER BY 2 DESC;
\qecho '-- clés de newProfile (attendues : yearOfBirth, gender, location...)'
SELECT k AS cle, count(*) AS profils
FROM idrepo.anonymous_profile,
     jsonb_object_keys(CASE WHEN jsonb_typeof(cast(profile AS jsonb) -> 'newProfile') = 'object'
                            THEN cast(profile AS jsonb) -> 'newProfile' ELSE '{}'::jsonb END) AS k
GROUP BY 1 ORDER BY 2 DESC;
\qecho '-- processus x genre ; part avec année de naissance et lieu'
SELECT cast(profile AS jsonb) ->> 'processName' AS processus,
       cast(profile AS jsonb) -> 'newProfile' ->> 'gender' AS genre,
       count(*) AS profils,
       count(*) FILTER (WHERE cast(profile AS jsonb) -> 'newProfile' ->> 'yearOfBirth' IS NOT NULL) AS avec_annee,
       count(*) FILTER (WHERE jsonb_typeof(cast(profile AS jsonb) -> 'newProfile' -> 'location') = 'array'
                          AND jsonb_array_length(cast(profile AS jsonb) -> 'newProfile' -> 'location') > 0) AS avec_lieu
FROM idrepo.anonymous_profile
GROUP BY 1, 2 ORDER BY 3 DESC;
\else
\qecho 'idrepo.anonymous_profile absente : instance antérieure à MOSIP 1.1.5.5, pas de source pour l âge et le sexe.'
SELECT table_name FROM information_schema.tables WHERE table_schema = 'idrepo' ORDER BY 1;
\endif
