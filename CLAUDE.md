# mosip-cdc : consignes de travail

Lire d'abord `../outfit.md` (état du travail et décisions) et `README.md` (architecture).

## Principes
- Le contrat `bi` appartient au backend (`mosip-bi-reporting`, migrations Flyway). Avant d'écrire un modèle `dm_*` ou
  la publication, relire les colonnes, clés et contraintes de la table cible dans les migrations, et la requête de
  `EnrolementRepository` (ou équivalent) qui la lit.
- Une nouvelle source suit le patron des pré-inscriptions et de l'enrôlement :
  1. connecteur Debezium aux seules colonnes utiles (`column.include.list`, jamais d'identité ; texte libre seulement
     après un relevé qui montre qu'il ne contient pas d'identifiant, et jamais publié tel quel vers `bi`, comme
     `registration.status_comment` rangé en motifs),
     prérequis DBA dans `sql/mosip/NN_prerequis_<base>.sql` (partie A en lecture seule, partie B une fois) ;
  2. topic créé dans `kafka/topics.sh` (une partition : dbt suit l'ordre des offsets) ;
  3. connecteur JDBC vers `lake.<topic avec _>` (`primary.key.mode=kafka`, `ExtractNewRecordState` avec
     `op,lsn,source.ts_ms`) ; table du lake créée à l'avance par un script `sql/traitement/` pour que dbt ne casse pas.
     Table très modifiée (ex. `regprc.registration`, 610 000 mises à jour par jour) : plutôt l'ODS en upsert
     (`primary.key.mode=record_key`, offset ajouté par `InsertField$Value` en `__kafka_offset`), topic compacté ;
  4. dbt : `dwh/<domaine>/stg_*` incrémental par `__connect_offset` (lake) ou `__kafka_offset` (ODS), faits
     `dm_<domaine>/*` en tables, droits par `+grants` et usage du schéma par `+post-hook` ;
  5. publication dans `scripts/publier-indicateurs.sh`, dans la transaction existante : table temporaire `n_<table>`
     (`LIKE bi.<table>`), puis `pg_temp.synchroniser` qui n'écrit que les lignes qui changent (jamais DELETE + INSERT
     de toute une table : WAL archivé, incident du 30/10/2026) ; codes résolus en identifiants `bi.zone`, regroupement
     après résolution ; droits `bi` par un script exécuté par `bi_owner`.
- Modèle reconstruit en entier : `unlogged` (réglage du projet) ; modèle incrémental : `unlogged=false` dans sa config.
- Correspondances de codes MOSIP dans `dbt/seeds/` ; un code inconnu compte en « non classé », jamais deviné.
- Pas de test `unique` sur une colonne déjà garantie par une clé primaire ou un index unique : il relit toute la table à
  chaque passage sans pouvoir échouer. Un test sur une grande table ne lit que ce qui a changé (offset, `maj_le`,
  index partiel), comme `assert_rid_uin_link_date_modifiee`.
- Une égalité de contrôle publiée dans le backend a son test singulier dans `dbt/tests/` (bloquant). Une anomalie de
  données (code inconnu, date modifiée) est une alerte (`severity: warn`) : un échec bloque toute la publication.
- RID : jamais publié vers `bi` ; seule son empreinte `hmac(rid, SUIVI_HMAC_CLE, 'sha256')` l'est (suivi d'un dossier).

## Style
- Français partout (commentaires, noms métier, messages). En-tête de chaque modèle : règle de calcul en `{#- … -#}`.
- Scripts SQL : en-tête qui dit quoi, par quel rôle, quand, et la commande `psql` exacte ; `\set ON_ERROR_STOP on`.
- Dans dbt, écrire `pg_catalog.date(...)` (EDB peut traduire `date` en timestamp).
- Fins de ligne LF (`.gitattributes`) ; vérifier qu'un fichier écrit depuis Windows n'a pas de CR.
- Jamais de mot de passe ni d'hôte MOSIP réel dans le dépôt : `<mot de passe>`, `<serveur MOSIP>`.

## Vérifier
- `outils/banc/` (voir son README) après toute modification de `dbt/` ou de `scripts/publier-indicateurs.sh` ;
  `bash -n` sur les scripts modifiés.
- Sur un poste ou le serveur avec dbt : `docker compose run --rm -T dbt build` (référence ; le banc ne le remplace pas).
- Ne jamais lancer de commande sur le serveur pipeline ni sur MOSIP : préparer, documenter dans `docs/`, les humains
  exécutent.
