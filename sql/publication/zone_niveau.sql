-- Met à jour bi.zone pour le niveau :n (variable psql), à partir de dwh.dim_zone. Appelé niveau par niveau, du haut
-- vers le bas, par scripts/publier-indicateurs.sh : le parent est toujours déjà en place.
-- Mise à jour par code : les identifiants restent stables (les tables de faits s'y réfèrent) ; une zone disparue de
-- MOSIP est gardée ; une ligne inchangée n'est pas réécrite.
INSERT INTO bi.zone (niveau, code, nom, parent_id, ordre)
SELECT z.niveau,
       z.code,
       z.nom,
       CASE WHEN z.niveau = 'region' THEN NULL
            ELSE coalesce(p.id, (SELECT id FROM bi.zone WHERE code = 'HORS_REFERENTIEL')) END,
       z.ordre
FROM dwh.dim_zone z
LEFT JOIN bi.zone p ON p.code = z.parent_code
WHERE z.niveau = :'n'
ON CONFLICT (code) DO UPDATE
   SET niveau = excluded.niveau, nom = excluded.nom, parent_id = excluded.parent_id, ordre = excluded.ordre
 WHERE (bi.zone.niveau, bi.zone.nom, bi.zone.parent_id, bi.zone.ordre)
       IS DISTINCT FROM (excluded.niveau, excluded.nom, excluded.parent_id, excluded.ordre);
