-- Fonction de la session de publication (schéma pg_temp : elle disparaît avec la connexion, rien n'est créé dans la
-- base). Inclus au début de la transaction par scripts/publier-indicateurs.sh.
--
-- pg_temp.synchroniser(cible, source, cles) : rend la table bi `cible` égale à la table temporaire `source` (mêmes
-- colonnes, créée par LIKE), en ne touchant QUE les lignes qui diffèrent :
--   1. supprime les lignes de la cible absentes de la source ou dont une valeur a changé (repérées par la clé
--      primaire `cles`) ;
--   2. insère les lignes de la source absentes de la cible (nouvelles ou changées).
-- Avant le 30/10/2026, chaque passage vidait puis rechargeait toutes les tables : 1,8 M de lignes pour
-- bi.fait_delai_jour toutes les 5 minutes, une table gonflée à 7 Go et environ 3 Go de journal (WAL) par passage,
-- archivés. La table temporaire n'est pas journalisée ; seules les différences le sont. Même transaction qu'avant :
-- l'API voit l'ancienne version jusqu'au COMMIT. EXCEPT compare aussi les valeurs nulles.
CREATE OR REPLACE FUNCTION pg_temp.synchroniser(p_cible text, p_source text, p_cles text[])
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_colonnes   text;
    v_jointure   text;
    v_supprimees bigint;
    v_inserees   bigint;
BEGIN
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
      INTO v_colonnes
      FROM pg_attribute a
     WHERE a.attrelid = p_cible::regclass AND a.attnum > 0 AND NOT a.attisdropped;
    SELECT string_agg(format('t.%1$I = d.%1$I', c), ' AND ')
      INTO v_jointure
      FROM unnest(p_cles) AS c;

    EXECUTE format('DELETE FROM %s t USING (SELECT %s FROM %s EXCEPT SELECT %s FROM %s) d WHERE %s',
                   p_cible, v_colonnes, p_cible, v_colonnes, p_source, v_jointure);
    GET DIAGNOSTICS v_supprimees = ROW_COUNT;

    EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM %s EXCEPT SELECT %s FROM %s',
                   p_cible, v_colonnes, v_colonnes, p_source, v_colonnes, p_cible);
    GET DIAGNOSTICS v_inserees = ROW_COUNT;

    RETURN format('%s : %s supprimées, %s insérées', p_cible, v_supprimees, v_inserees);
END;
$$;
