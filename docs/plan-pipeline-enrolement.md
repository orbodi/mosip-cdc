# Plan de mise en place du pipeline de l'enrôlement (25/10/2026, validé)

Ce plan met en œuvre `docs/conception-enrolement.md`, avec les indicateurs I1 à I11 de `docs/releve-enrolement.md` et
la maquette v3 (`maquette/prototype-enrolement-v3.html`). Il remplace la procédure de `docs/enrolement.md` (lot du
24/10), qui sera réécrite à la fin du lot 4.

Règle de travail : Claude écrit et teste le code sur le banc (`outils/banc/`). **Les humains exécutent** tout ce qui
touche au serveur, à la BD traitement ou à MOSIP, dans l'ordre ci-dessous. Rien n'est commité ni poussé sans demande
explicite.

## Avancement

| Lot | État au 25/10/2026, 3 h 30 |
|---|---|
| 0 | fait : brouillon du 24/10 retiré (`lake-regprc.json`, `14_lake_regprc.sql`, `stg_regprc__niu.sql`) |
| 1 | écrit : connecteurs, topics, `14_ods_regprc.sql`, `15_lake_regprc.sql`, prérequis MOSIP, contrôle de santé |
| 2, 3 | écrits et vérifiés sur le banc (incrémental, passage à vide et `--full-refresh` identiques) |
| 4 | écrit et vérifié sur le banc : migration V7 (backend, non commitée), publication, `charger-suivi.sh`, `17_prerequis_proprietaire.sql` |
| 1 à 4 | **à mettre en service par l'exploitation** : `docs/enrolement.md`, section « Mise en service » |
| 5 | à faire : API et front |

Écarts au plan, décidés en l'écrivant :
- un statut inconnu donne le devenir `non_classe` et une **alerte**, pas un échec : un test en échec bloquerait toute
  la publication, pré-inscriptions comprises (le contrat `bi` a déjà une colonne `non_classees`) ;
- les étapes à faible effectif sont regroupées en « Autres étapes » par l'API (lot 5), pas dans dbt : `bi` garde le
  détail de chaque étape ;
- `BIOGRAPHIC_VERIFICATION` est libellée « Déduplication biométrique » (étape BioDedupeStage), et non « Vérification
  biographique » comme dans le prototype : à corriger au front ;
- le journal des recherches (`bi.journal_suivi`) et le rôle de l'API pour le suivi viennent avec le lot 5 (migration
  V8) : ils dépendent de la façon dont l'API se connecte ;
- prérequis ajouté : extension `pgcrypto` sur `mosip_bi` (`17_prerequis_proprietaire.sql`).

## Vue d'ensemble

| Lot | Contenu | Livre | Dépend de |
|---|---|---|---|
| 0 | Préalables et nettoyage du brouillon du 24/10 | décisions, dépôt propre | validation de la conception |
| 1 | Capture : `registration`, `rid_uin_link`, `registration_list` | ODS et journal alimentés en continu | lot 0, DBA |
| 2 | Data warehouse : `dwh.suivi_inscription` | une ligne par inscription, jalons et devenir | lot 1 |
| 3 | Data mart : faits, stocks, histogrammes, suivi | `dm_enrolement.*` testé | lot 2 |
| 4 | Contrat `bi` (migration V7) et publication | `bi.*` à jour toutes les 5 minutes | lot 3, backend |
| 5 | API et front (branche `dashboard`) | page Enrôlement v3 en production | lot 4 |
| 6 | Enrichissement démographique (âge, sexe, nationalité) | profil des NIU | nom de l'API, lot 4 |
| 7 | `registration_transaction` sans snapshot | étapes franchies dans le suivi | lot 4 |
| 8 | Impression et remise (`printing_*`) | jalons de la carte, page Impression | structures des tables |

Les lots 1 à 5 forment la **phase 1** (I1 à I11, suivi en jalons). Les lots 6, 7 et 8 sont les phases 2, 3 et 4.

## Lot 0 : préalables

**À trancher ou à obtenir avant d'écrire le code** :
1. Validation de la conception et du design v3 par le responsable.
2. **Clé HMAC du suivi** : variable `SUIVI_HMAC_CLE` du fichier `compose/.env` (**décision du responsable,
   25/10/2026**). Ce fichier n'est jamais versionné (`.gitignore`), il est en mode 600 et il est déjà lu par le script
   de publication et par l'API (`docker-compose.dashboard.yml`). Générée une fois par `openssl rand -hex 32` ;
   modèle dans `compose/.env.example`. À sauvegarder avec les autres secrets du `.env` : la perdre oblige à recalculer
   toutes les empreintes.
3. **DBA MOSIP** :
   - droits de lecture du rôle de capture sur `registration`, `rid_uin_link`, `registration_list` (partie B de
     `sql/mosip/02_prerequis_regprc.sql`, à réécrire pour les trois tables) ;
   - `max_slot_wal_keep_size` borné (un slot arrêté ne doit pas remplir le disque de MOSIP) ;
   - un créneau creux pour le snapshot (≈ 19 M de lignes lues sur les trois tables).
4. Place disque sur la BD traitement : ODS ≈ 3 Go (trois tables, colonnes réduites), journal `rid_uin_link` ≈ 1 Go par
   an. Estimations à confirmer après le snapshot.

**Nettoyage du brouillon du 24/10** (fichiers non commités) :
- supprimer `kafka/connecteurs/lake-regprc.json`, `sql/traitement/14_lake_regprc.sql`,
  `dbt/models/dwh/regprc/stg_regprc__niu.sql` et les tests liés ;
- reprendre `stg_regprc__registration.sql`, `dm_enrolement/*`, `topics.sh`, `publier-indicateurs.sh`,
  `check-health.sh`, `ref_regprc_statuts.csv` selon les lots 1 à 4 ;
- garder le banc (`outils/banc/`) et l'adapter à l'ODS.

## Lot 1 : capture

**Fichiers** :
- `kafka/connecteurs/mosip-regprc-cdc.json` : une seule source Debezium (slot `mosip_regprc_cdc`, publication
  `dbz_publication`, heartbeat), `table.include.list` sur les trois tables, `column.include.list` limité aux colonnes
  de la conception. **`uin` et `civil_registry_number` ne sont jamais listées** : elles ne quittent pas MOSIP.
- trois topics (une partition chacun, pour garder l'ordre) :

  | Topic | Politique | Raison |
  |---|---|---|
  | `mosip.regprc.registration` | compacté | ≈ 620 000 événements par jour ; seul l'état courant compte, et le topic compacté permet de reconstruire l'ODS |
  | `mosip.regprc.rid_uin_link` | rétention 28 jours | journal complet des changements (≈ 35 000 par jour) |
  | `mosip.regprc.registration_list` | compacté | état courant de la synchronisation |

- connecteurs JDBC (même image que les pré-inscriptions) :
  - `ods-regprc-registration` → `ods.regprc_registration` (upsert sur `id`) ;
  - `ods-regprc-rid-uin-link` → `ods.regprc_rid_uin_link` (upsert sur `id`) ;
  - `lake-regprc-rid-uin-link` → `lake.mosip_regprc_rid_uin_link` (ajout, clé = offset Kafka) ;
  - `ods-regprc-registration-list` → `ods.regprc_registration_list` (upsert sur `id`).
  Chaque ligne de l'ODS reçoit l'**offset Kafka** et l'heure du message (transformation `InsertField`) : dbt ne relit
  que ce qui a changé depuis son dernier passage.
- `sql/traitement/14_ods_regprc.sql` : tables de l'ODS et du lake créées à l'avance, index sur l'offset et sur
  `reg_id`, droits de lecture pour `dbt_runner`.
- `kafka/topics.sh` : les trois topics et le heartbeat.
- `scripts/check-health.sh` : état des cinq connecteurs, retard du slot, âge du dernier message.

**Mise en service (humains)** :
1. BD traitement : `14_ods_regprc.sql`.
2. Serveur pipeline : `kafka/topics.sh`.
3. Créer les quatre connecteurs JDBC, **puis** la source (son snapshot démarre aussitôt).
4. Suivre le snapshot : retard du slot côté MOSIP, débit des connecteurs, nombre de lignes de l'ODS.

**Critères d'acceptation** :
- ODS = MOSIP, à quelques minutes près : `count(*)` des trois tables comparé (relevé du 24/10 : 6 360 418
  `registration`, 6 362 660 `registration_list`, ≈ 6,0 M `rid_uin_link`) ;
- aucune colonne `uin` ni `civil_registry_number` dans le lake, l'ODS ni les topics (vérification par
  `information_schema` et lecture d'un message) ;
- retard de bout en bout (MOSIP → ODS) sous 1 minute en régime courant ;
- slot qui avance (heartbeat) même la nuit.

**Retour arrière** : supprimer la source, puis le slot côté MOSIP (DBA). Les pré-inscriptions et le référentiel ne
sont pas touchés (autres connecteurs, autres slots).

## Lot 2 : data warehouse

**Modèles dbt** (`dbt/models/dwh/regprc/`) :
- `stg_regprc__registration`, `stg_regprc__rid_uin_link`, `stg_regprc__registration_list` : vues sur l'ODS,
  colonnes renommées, types fixés ;
- **`dwh.suivi_inscription`** (incrémental, `unique_key = rid`, filtre sur les offsets plus récents que le dernier
  passage) : une ligne par inscription, avec
  - centre (5 chiffres), poste (10 chiffres), type ;
  - jalons : `enrole_le` (horodatage du RID), `synchronise_le`, `refus_poste`, `recu_le`, `niu_le` ;
  - `status_code`, étape, dernière transaction ;
  - `devenir` selon la règle I4 ;
  - ancienneté de la dernière transaction (pour « bloqué > 30 jours ») ;
  - colonnes démographiques vides jusqu'au lot 6 ;
  - `maj_le` : heure du dernier changement, qui sert à la publication incrémentale du suivi (lot 4) ;
- seeds :
  - `ref_regprc_etapes.csv` : code de transaction → libellé français et ordre du traitement (Refus au poste,
    Validation opérateur et superviseur, Doublon démographique…) ;
  - `ref_regprc_statuts.csv` : statut → devenir (I4) ;
  - `ref_delai_classes.csv` : classes de délai (heure par heure jusqu'à 48 h, puis jour par jour).

**Tests dbt (bloquants)** :
- `suivi_inscription` a autant de lignes que `ods.regprc_registration` ;
- `devenir` jamais nul ; tout statut inconnu fait échouer le test (pas de « non classées » silencieuses) ;
- toute inscription PROCESSED a un `niu_le` ; aucune REJECTED n'en a (constats du relevé, étape 3).

**Tests en alerte** : `entry_date` modifiée après coup (journal du lake) ; préfixe de RID absent du référentiel.

**Durée d'un passage** : le premier passage (`--full-refresh`) lit 6,4 M de lignes. Ensuite, chaque passage ne traite
que les changements des 5 dernières minutes (≈ 2 000 inscriptions). Objectif : moins de 2 minutes par passage, pour
garder la cadence de 5 minutes avec les pré-inscriptions. À mesurer au premier passage réel.

## Lot 3 : data mart

**Modèles** (`dbt/models/dm_enrolement/`), tous calculés depuis `dwh.suivi_inscription` :

| Modèle | Grain | Indicateurs |
|---|---|---|
| `fait_enrolement_jour` (existant, réécrit) | jour de réception × centre × sexe × tranche × type | I1, I2 cohorte, I4, I5 total |
| `fait_niu_jour` (existant, réécrit) | jour du NIU × centre × type | I2 flux, I3 |
| `fait_arret_etape_jour` | jour de réception × centre × type × devenir × étape | I5, I6 |
| `stock_en_cours` | centre × étape × ancienneté (< 7 j, 7 à 30 j, > 30 j) | I7 |
| `fait_delai_jour` | jour × centre × mesure × classe de délai | I8, I9 (médiane et 90e centile exacts) |
| `stock_synchro_non_recue` | centre × ancienneté | I10 |
| `suivi_dossier_maj` | inscriptions changées depuis la dernière publication | I11 |
| `fraicheur_enrolement` (existant) | une ligne | pastille de mise à jour |

**Tests bloquants** (repris de la revue de design) :
- NIU + en cours + échoués + rejetés = inscriptions, par jour et par centre ;
- somme des étapes = total du devenir, pour les rejetés, les échoués et les en-cours (lignes « Autres étapes »
  comprises) ;
- NIU par jour du NIU = NIU par jour de réception, sur toute la durée ;
- somme des classes de délai = nombre de NIU (I8) et de paquets reçus (I9).

**Contrôle de cohérence avec le relevé** : au premier passage, comparer les totaux aux chiffres de
`releve-enrolement.md` (étapes 2 et 5). Un écart de plus de quelques centaines s'explique ou bloque la suite.

## Lot 4 : contrat `bi` et publication

**Backend (`mosip-bi-reporting`, branche `dashboard`)** : migration Flyway **V7**, en ajout seul :
- `bi.fait_arret_etape_jour`, `bi.stock_en_cours`, `bi.fait_delai_jour`, `bi.stock_synchro_non_recue`,
  `bi.fait_niu_nationalite_jour` ;
- `bi.suivi_dossier` : clé = empreinte HMAC du RID (`bytea`), aucune colonne RID ; rôle de lecture dédié
  `api_suivi`, distinct de `api_reader` ;
- `bi.journal_suivi` : utilisateur, heure, résultat (trouvé, introuvable, hors région, refusé), **sans le RID ni son
  empreinte** ;
- droits pour `publisher`.

**Publication** (`scripts/publier-indicateurs.sh`) :
- les faits et les stocks (quelques milliers à quelques centaines de milliers de lignes) : remplacement complet dans
  la transaction existante, comme aujourd'hui ;
- **le suivi (6,4 M de lignes) en incrémental** : `INSERT … ON CONFLICT (empreinte) DO UPDATE` des seules lignes de
  `suivi_dossier_maj`, empreinte calculée à ce moment par `hmac(rid, :'cle', 'sha256')`. La clé vient de `SUIVI_HMAC_CLE`
  (`compose/.env`) et passe à `psql` par une variable, jamais écrite dans le dépôt ni dans les journaux (pas de
  `set -x` dans le script) ;
- premier chargement du suivi : une seule fois, hors de la transaction des 5 minutes (script
  `scripts/charger-suivi.sh`), par tranches de 500 000 lignes.

**Ordre de mise en service** :
1. Déployer le backend avec V7 (tables vides ; l'API existante continue de répondre).
2. BD traitement : `16_droits_bi_enrolement.sql` mis à jour.
3. `git pull` de `mosip-cdc` sur le serveur ; le cron lance dbt (premier passage long, les suivants sautent leur tour
   grâce au verrou).
4. `scripts/charger-suivi.sh`, une fois.
5. Vérifier : `bi.fait_enrolement_jour` totalise le même nombre d'inscriptions que l'ODS ; la page actuelle continue
   de s'afficher.

**Retour arrière** : revenir au commit précédent de `mosip-cdc` ; les tables V7 restent vides et ne gênent rien.

## Lot 5 : API et front

**API** :
- routes `GET /enrolement/etapes`, `/en-cours`, `/delais`, `/synchronisation`, `/profil` ;
- `devenir` (règle I4, nombre de bloqués), `territoire` (délai médian en heures, étape dominante des rejets),
  `centres` (onglet « Remontée la plus lente ») ;
- `POST /enrolement/suivi` : RID dans le corps, contrôle de 29 chiffres, empreinte calculée en mémoire, journal, RID
  jamais renvoyé ni journalisé ; ni plafond de recherches (décision du 26/10/2026) ni portée régionale (accès à tout
  le Togo, décision du 25/10/2026) ;
- tests d'intégration sur le banc avec les vraies migrations.

**Front** :
- blocs et fenêtre de suivi de la maquette v3 (prototype de référence) ;
- jetons `--statut-en-cours` #B07D00, `--statut-echoue` #D2632A, `--statut-bloque` #6B4A00 pour toute l'application ;
- tests (Vitest, Playwright avec l'API simulée de `e2e/api.ts` étendue) ;
- relecture avec le skill `revue-design-bi-anid` avant livraison, à 1 440, 1 000 et 390 px.

## Lot 6 : enrichissement démographique (phase 2)

**Livré le 29/10/2026** (mise en service : `docs/enrolement.md`, « Profil des NIU par l'ID Repository »). API : ID
Repository, `/idrepository/v1/identity/idvid/{RID}`, appelé avec le RID (accepté, vérifié par le responsable le
29/10/2026), jamais avec le NIU ; seuls les NIU sont enrichis (l'ID Repository ne connaît que les identités créées).
Écarts au plan ci-dessous : ODS `ods.regprc_enrichissement` (nom des autres tables de l'enrôlement) ; un seul modèle
`dm_enrolement.fait_niu_profil_jour`, regroupé à la publication en `bi.fait_niu_profil_jour` et
`bi.fait_niu_nationalite_jour` ; pas de colonne démographique dans `suivi_inscription` ; région du centre.

Plan initial :
- jobs Spark sur le modèle des pré-inscriptions (`enrichissement_flux.py`, `rattrapage_stock.py`) : genre, année et
  mois de naissance, nationalité seulement ;
- topic compacté `mosip.regprc.enrichissement`, ODS `ods.enrichissement_inscription` ;
- rattrapage du stock (≈ 6 M dossiers, environ 5 jours aux débits des pré-inscriptions), dans des créneaux qui ne
  chevauchent pas le rattrapage des pré-inscriptions ;
- dbt : colonnes démographiques de `suivi_inscription`, `fait_niu_profil_jour`, `fait_niu_nationalite_jour`.

## Lot 7 : `registration_transaction` (phase 3)

- capture **sans snapshot** (nouvelles lignes seulement), table du lake partitionnée par mois ;
- 676 000 lignes par jour : rétention à décider (par exemple 13 mois) ;
- livre : étapes franchies dans la frise du suivi, durée de chaque étape, reprises en boucle.

## Lot 8 : impression et remise (phase 4)

Bloqué par : structures des tables `printing_*` (déjà dans `dbz_publication`). Même démarche que pour l'enrôlement :
relevé étape par étape, puis conception.

## Risques et parades

| Risque | Parade |
|---|---|
| Slot arrêté qui remplit le disque de MOSIP | `max_slot_wal_keep_size`, heartbeat, alerte de `check-health.sh` sur le retard du slot |
| Snapshot qui charge MOSIP | créneau creux choisi avec le DBA ; une seule source pour les trois tables |
| Passage dbt de plus de 5 minutes | modèles incrémentaux, durée suivie dans `analytique.log` ; un passage en retard saute le suivant au lieu de s'empiler |
| Un test en échec bloque toute la publication, pré-inscriptions comprises | tests d'abord passés sur le banc ; erreurs de données en alerte, pas en blocage, sauf les égalités |
| Fuite du RID | jamais publié vers `bi` ; empreinte HMAC ; corps de requête jamais journalisé ; dépôts à rendre privés (`mosip-bi-reporting` est public) |
| Clé HMAC perdue ou changée | sauvegarder `compose/.env` avec les autres secrets ; sinon relancer `charger-suivi.sh` et redémarrer l'API |

## Ce qui est attendu de chacun

- **Responsable** : validation de la conception et du design ; nom de l'API d'enrichissement. (Clé HMAC : tranché,
  `compose/.env`.)
- **DBA MOSIP** : droits, `max_slot_wal_keep_size`, créneau du snapshot.
- **Exploitation** : exécution des étapes de mise en service, dans l'ordre de chaque lot.
- **Claude** : code et tests des lots 0 à 5, procédure mise à jour, `outfit.md` tenu à jour.
