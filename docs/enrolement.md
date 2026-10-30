# Enrôlement : chaîne de données et mise en service

Conception : `docs/conception-enrolement.md` ; plan : `docs/plan-pipeline-enrolement.md` (ce document couvre les lots 1
à 4) ; indicateurs I1 à I11 : `docs/releve-enrolement.md`.

```
mosip_regprc                      Kafka (1 partition par topic)          BD traitement mosip_bi
registration ──────┐              mosip.regprc.registration (compacté)  → ods.regprc_registration      (upsert)
rid_uin_link ──────┼─ Debezium ─→ mosip.regprc.rid_uin_link (28 j)      → ods.regprc_rid_uin_link      (upsert)
registration_list ─┘  mosip-      │                                     → lake.mosip_regprc_rid_uin_link     (journal)
                      regprc-cdc  mosip.regprc.registration_list (cpt.) → ods.regprc_registration_list (upsert)
                                                                              │ dbt toutes les 5 min
                                       dwh.suivi_inscription (une ligne par RID) → dm_enrolement.* → publication → bi.*

Profil des NIU (lot 6) : rid_uin_link (lien créé) ─→ Spark ─→ ID Repository, appelé avec le RID
   ─→ mosip.regprc.enrichissement (compacté) → lake.mosip_regprc_enrichissement (journal) + ods.regprc_enrichissement
   ─→ dbt : stg_regprc__enrichissement → dm_enrolement.fait_niu_profil_jour → bi.fait_niu_profil_jour,
            bi.fait_niu_nationalite_jour
```

## Ce qui est capté

| Table MOSIP | Colonnes | Jamais |
|---|---|---|
| `registration` | `id` (RID), `reg_type`, `status_code`, `latest_trn_type_code`, `latest_trn_status_code`, `latest_trn_dtimes`, `reg_stage_name`, `status_comment` (depuis le 26/10/2026), `cr_dtimes`, `upd_dtimes` | `cr_by`, `upd_by`… |
| `rid_uin_link` | `id`, `reg_id` (RID), `reg_type`, `entry_date` | **`uin`, `civil_registry_number`** |
| `registration_list` | `id`, `reg_id` (RID), `reg_type`, `client_status_code`, `cr_dtimes`, `upd_dtimes` | noms, téléphones, adresses |

- **ODS** (état courant, mis à jour sur place) pour les trois tables : `registration` reçoit environ 610 000 mises à
  jour par jour, un journal complet serait trop lourd. Chaque ligne porte l'offset Kafka du message qui l'a écrite
  (`__kafka_offset`) : dbt ne relit que ce qui a changé.
- **`status_comment`** (motif de MOSIP, texte technique en anglais) : capté depuis le 26/10/2026 pour expliquer les
  rejets, échecs et en cours (relevé R13 : une vingtaine de messages pour les rejets, une quarantaine pour les échecs,
  aucun identifiant de personne). Le texte reste dans l'ODS ; dbt le range dans un motif
  (`seeds/ref_regprc_motifs.csv`) et seul le code du motif va vers `bi`.
  Les inscriptions captées avant le 27/10/2026 ont été complétées une fois par `scripts/rattraper-status-comment.sh`
  (lignes vides seulement, relançable).
- **Journal** (lake) pour `rid_uin_link` seulement : il sert à repérer un `entry_date` modifié après coup (alerte).
- **Profil des NIU** (lot 6, 29/10/2026) : pour chaque inscription qui a un NIU, l'ID Repository de MOSIP
  (`/idrepository/v1/identity/idvid/{RID}`) est appelé **avec le RID, jamais avec le NIU** (le NIU n'est capté nulle
  part). De la réponse, le job ne garde que le genre, la nationalité, l'année et le mois de naissance ; le NIU, les
  noms, le téléphone, la pièce d'identité, la date complète, les lieux, la profession ne sont ni gardés ni journalisés,
  et le message d'erreur de MOSIP non plus (il peut reprendre l'identifiant). Le RID figure dans l'adresse de l'appel :
  les journaux de la passerelle MOSIP le voient, comme le `prereg_id` des pré-inscriptions.
- Le RID est en clair dans l'ODS, le lake et le `dwh`, comme le `prereg_id`. Vers `bi`, seule son **empreinte HMAC**
  est publiée (suivi d'un dossier), avec la clé `SUIVI_HMAC_CLE` de `compose/.env`.

## Règles de calcul (dbt)

`dwh.suivi_inscription` : une ligne par RID reçu (`registration`) ou seulement synchronisé (`registration_list`).
- **Jalons** : enrôlé (14 derniers chiffres du RID), synchronisé (première synchronisation), reçu (`cr_dtimes`), NIU
  (`entry_date` du lien).
- **Devenir** (règle I4) : `niu` s'il y a un lien, quel que soit le statut ; sinon selon `seeds/ref_regprc_statuts.csv`
  (`en_cours`, `echoue`, `rejete`) ; un statut inconnu = `non_classe` (alerte, jamais deviné) ; synchronisé non reçu =
  `non_recu`.
- **Étape** : dernière transaction (`latest_trn_type_code`) ; un rejet à `VALIDATE_PACKET` d'un paquet refusé au poste
  devient `REFUS_POSTE`. Libellés et ordre : `seeds/ref_regprc_etapes.csv`.
- **Motif** (décision du 26/10/2026) : `dwh.motif_inscription`, recalculée en entier à chaque passage pour les
  inscriptions non `PROCESSED` : étape `reg_stage_name` (libellés `seeds/ref_regprc_stages.csv`) et motif tiré de
  `status_comment` par les règles de `seeds/ref_regprc_motifs.csv` (expressions régulières sans distinction de casse,
  la plus petite priorité gagne). Un message qu'aucune règle ne reconnaît compte en « Motif non répertorié » (alerte
  `assert_enrolement_motifs_inconnus`, qui liste le message, chiffres masqués) : ajouter une ligne au catalogue, prise
  en compte au passage suivant sans `--full-refresh`. Le texte de MOSIP ne quitte pas le data warehouse. Pour chaque
  motif, le catalogue donne un libellé qui traduit fidèlement le message de MOSIP (un message distinct = un motif, par
  exemple empreintes, iris et visage séparés) et une ligne « À vérifier » (`piste`, publiée en `motif_piste`, V10) :
  ce que le message veut dire et où chercher (décision du 28/10/2026).
- **Centre** : 5 premiers chiffres du RID ; un code absent de `bi.zone` va sous « Centre non référencé ».
- **Incrémental** : seuls les RID touchés depuis le passage précédent sont recalculés. Les chiffres qui dépendent de
  l'heure (ancienneté des en-cours, synchronisés de plus de 7 jours) sont calculés à chaque passage dans
  `dm_enrolement`.

| Modèle `dm_enrolement` | Publié dans | Indicateurs |
|---|---|---|
| `fait_enrolement_jour` | `bi.fait_enrolement_jour` | I1, I2 cohorte, I4 |
| `fait_niu_jour` | `bi.fait_niu_jour` | I2 flux, I3 |
| `fait_arret_etape_jour` | `bi.fait_arret_etape_jour` (V7) | I5, I6 |
| `stock_en_cours` | `bi.stock_en_cours` (V7) | I7, « dont bloqués » |
| `fait_arret_motif_jour` | `bi.fait_arret_motif_jour` (V9) | I5, I6 par étape et motif |
| `stock_en_cours_motif` | `bi.stock_en_cours_motif` (V9) | I7 par étape et motif |
| `fait_delai_jour` | `bi.fait_delai_jour` (V7) | I8, I9 |
| `stock_synchro_non_recue` | `bi.stock_synchro_non_recue` (V7) | I10 |
| `suivi_dossier` (vue) | `bi.suivi_dossier` (V7), par empreinte, lignes changées seulement | I11 |
| `fait_niu_profil_jour` (lot 6) | `bi.fait_niu_profil_jour` (V4) et `bi.fait_niu_nationalite_jour` (V7), regroupés à la publication | profil des NIU : sexe, tranche d'âge, nationalité |
| `fraicheur_enrolement` | `bi.source_fraicheur('enrolement')` | pastille de mise à jour |

**Profil des NIU** (`fait_niu_profil_jour`, lot 6) : les NIU de `fait_niu_jour`, au même jour de génération, par
région du **centre** (`dim_centre_region`, « Hors référentiel » si le centre n'est rattaché à aucune région), sexe
(« Femme » → F, « Homme » → H, aussi FLE et MLE ; toute autre valeur → I, alerte `assert_enrolement_genres_inconnus`),
tranche d'âge (années révolues au jour du NIU, d'après l'année et le mois de naissance ; tranches des pré-inscriptions)
et nationalité (libellé de la liste MOSIP « nationality » si la valeur y est un code, sinon la valeur telle quelle).
Un NIU pas encore enrichi compte en I, âge inconnu, « Non renseignée » : le total égale toujours les NIU générés.

**Contrôles bloquants** (rien n'est publié en cas d'échec, pré-inscriptions comprises) : somme des devenirs =
inscriptions ; ODS = suivi = faits ; NIU flux = NIU cohorte ; profil des NIU = NIU générés, jour par jour ; étapes = Devenir ; motifs = Devenir ; histogrammes
complets ; codes uniques dans les seeds. L'unicité du RID n'est pas un test : clés primaires de l'ODS et index unique de
`dwh.suivi_inscription` (un doublon fait échouer ce modèle ; allègement du 25/10/2026, un passage dbt de 88 s).
**Alertes** : centre non référencé, statut ou étape inconnus, horodatage du RID illisible, `entry_date` modifiée,
commentaire de MOSIP non répertorié, étape `reg_stage_name` absente de `ref_regprc_stages.csv`, genre de l'ID Repository
non reconnu.

## Mise en service

L'ordre compte. **Les étapes 1 à 5 passent avant la mise à jour du dépôt sur le serveur (étape 6)** : sans les tables
de l'ODS et de `bi`, `dbt build` ou la publication échouent, et les pré-inscriptions ne sont plus publiées non plus.

**Avant tout**
- `compose/.env` du serveur : ajouter `SUIVI_HMAC_CLE`, générée une fois par `openssl rand -hex 32` ; sauvegarder le
  fichier avec les autres secrets.
- DBA MOSIP : parties A puis B de `sql/mosip/02_prerequis_regprc.sql` ; renvoyer les résultats de la partie A (les
  trois tables doivent être dans `dbz_publication`). Convenir d'un créneau creux pour le snapshot (≈ 19 M de lignes).
  **Fait le 25/10/2026** (EDB 12.16 ; publication complète ; SELECT sur les trois tables) ; topics créés et
  `mosip-regprc-cdc` créé à 12 h 05, snapshot en cours.

**BD traitement**
1. Propriétaire de `mosip_bi` et des schémas `lake` et `ods` (`enterprisedb`) : `sql/traitement/17_prerequis_proprietaire.sql`
   (extension pgcrypto, usage du schéma `ods` pour dbt, schéma `dm_enrolement` propriété de `dbt_runner`, contrôles).
2. `ods_writer` : `sql/traitement/14_ods_regprc.sql`.
3. `ingest_writer` : `sql/traitement/15_lake_regprc.sql` (crée aussi l'index de l'alerte « entry_date modifiée »).
   Installation antérieure au 25/10/2026, 18 h 30 : `sql/traitement/18_index_lake_regprc.sql`, une fois, à tout moment.

**API (mosip-bi-reporting, branche `dashboard`)**

4. Déployer l'API avec la migration `V7__enrolement_etapes_delais_suivi.sql` : Flyway crée les tables, vides ; la page
   actuelle continue de s'afficher.
5. `bi_owner` : `sql/traitement/16_droits_bi_enrolement.sql`.

**Serveur pipeline**

6. Mise à jour du dépôt (`git pull`). Au passage suivant du cron, dbt crée les nouveaux modèles et publie un enrôlement
   vide.
7. Topics, dans l'interface Kafka (ou `kafka/topics.sh`) : une partition chacun, réglages de `topics.sh`. **Vérifier
   les quatre en ligne de commande avant de créer la source**, car l'interface peut masquer les topics qui commencent
   par `__` :
   `docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list | grep regprc`.
   Sans `__debezium-heartbeat.mosip_regprc`, le snapshot passe, puis Debezium se bloque dès le suivi en continu
   (`UNKNOWN_TOPIC_OR_PARTITION` dans les journaux de `mosip-cdc-connect`) et le slot retient les journaux de MOSIP
   (incident du 25/10/2026, 13 h 35 à 14 h 30).
8. Connecteurs, créés dans l'interface Kafka (nom = nom du fichier de `kafka/connecteurs/`, configuration = son
   contenu, mots de passe et hôte reportés). La source peut être créée avant les connecteurs JDBC : les messages
   attendent dans Kafka (topics compactés ou 28 jours). Son snapshot démarre aussitôt : créneau creux.
   Les connecteurs JDBC écrivent dans le schéma par défaut de leur rôle : vérifier que `ods_writer` a
   `search_path = ods` et `ingest_writer` `search_path = lake`, comme pour les pré-inscriptions. Pendant le snapshot,
   le slot `mosip_regprc_cdc` reste inactif et son retard monte ; il passe actif à la fin.
9. Suivre le snapshot : `select count(*)` des trois tables de l'ODS (cibles du relevé : ≈ 6,36 M `registration`,
   6,02 M `rid_uin_link`, 6,36 M `registration_list`) ; retard du slot (`scripts/check-health.sh`).
10. Après le snapshot, le premier passage dbt traite les 6,4 M de lignes (plusieurs minutes ; le cron saute les
    passages suivants tant qu'il n'est pas fini). Le cron publie tout, sauf le suivi d'un dossier (plus de
    200 000 lignes) : le journal `analytique.log` le signale.
11. Charger le suivi d'un dossier, une fois : `scripts/charger-suivi.sh` (par lots de 500 000, prend le verrou de la
    chaîne analytique). Ensuite, chaque passage ne publie que les dossiers changés (≈ 2 000 toutes les 5 minutes).
12. Vérifier :
    - `scripts/check-health.sh` reste muet ;
    - `bi.fait_enrolement_jour` totalise le même nombre d'inscriptions que `ods.regprc_registration` ;
    - comparer les totaux au relevé (`docs/releve-enrolement.md`, étapes 2 et 5) : écart de quelques centaines au plus ;
    - aucune colonne `uin` ni `civil_registry_number` dans l'ODS, le lake ni les messages Kafka.

### Motifs (lot 5c, 27/10/2026)

1. Connecteur : `status_comment` ajouté à `column.include.list` et à l'instantané de `regprc.registration`, après
   `ALTER TABLE ods.regprc_registration ADD COLUMN status_comment` (script 14).
2. Rattrapage unique des inscriptions captées avant : `scripts/rattraper-status-comment.sh`.
3. Backend : migration V9 (`bi.fait_arret_motif_jour`, `bi.stock_en_cours_motif`) appliquée au redémarrage de l'API,
   route `GET /api/v1/enrolement/motifs`.
4. **Sous le verrou de la chaîne analytique** (aucun passage entre les deux) : `git pull` de `mosip-cdc` (nouveaux
   modèles et publication), puis droits de `publisher` sur les tables V9 (script 16, par `bi_owner`). Sans les droits,
   la publication échouerait (transaction annulée, chiffres précédents gardés) jusqu'à leur octroi.

### Motif dans le suivi d'un dossier (29/10/2026)

Le suivi d'un dossier donne le motif de MOSIP d'un dossier rejeté, échoué ou en cours. `bi.suivi_dossier` n'en garde
que le code (colonne `motif`) ; libellé et message type sont dans `bi.ref_motif`, republiée à chaque passage depuis
`dm_enrolement.ref_motif` : un libellé corrigé s'applique sans republier les dossiers.

1. Backend : migration V11 (`bi.suivi_dossier.motif`, `bi.ref_motif`) appliquée au redémarrage de l'API.
2. **Sous le verrou de la chaîne analytique** : `git pull` de `mosip-cdc`, puis droits de `publisher` sur
   `bi.ref_motif` (script 16, par `bi_owner`). Sans les droits, la publication échouerait (transaction annulée).
3. Rattrapage unique des dossiers déjà publiés (la publication ne reprend que les dossiers modifiés) :
   `scripts/rattraper-motif-suivi.sh` (≈ 350 000 dossiers, empreinte calculée pour ceux qui ont un motif ; relançable,
   ne réécrit que les motifs qui changent).

### Profil des NIU par l'ID Repository (lot 6, 29/10/2026)

Rien ne change pour les pré-inscriptions : leurs jobs gardent leurs messages, leurs topics et leur point de reprise
(option `--source`, `prereg` par défaut). L'ordre compte : sans les tables et les droits, la publication échoue.

**Avant tout** : `compose/.env` du serveur. Si l'ID Repository demande d'autres identifiants que la pré-inscription,
ajouter `IDREPO_APP_ID`, `IDREPO_CLIENT_ID` et `IDREPO_SECRET_KEY` (et `IDREPO_URL` si la passerelle diffère) ;
laissées vides ou absentes, ce sont celles de `API_*` qui servent. Ne jamais les écrire ailleurs.

**BD traitement**
1. `ingest_writer` : `sql/traitement/19_lake_regprc_enrichissement.sql`.
2. `ods_writer` : `sql/traitement/20_ods_regprc_enrichissement.sql` (table et droits de `spark_reader`).

**API (mosip-bi-reporting, branche `dashboard`)**
3. Déployer l'API : `/age-sexe` renvoie aussi les nationalités (aucune migration ; tables V4 et V7 déjà en place).
4. `bi_owner` : `sql/traitement/16_droits_bi_enrolement.sql` (droits de `publisher` sur `bi.fait_niu_profil_jour`),
   **avant** l'étape 5 : sans eux, la publication échouerait (transaction annulée, chiffres précédents gardés).

**Serveur pipeline**
5. `git pull` de `mosip-cdc`. Au passage suivant, dbt crée `stg_regprc__enrichissement` (vide), `dim_centre_region` et
   `fait_niu_profil_jour`, et publie le profil : tous les NIU en « Non renseignée », pyramide vide, jusqu'aux premières
   réponses.
6. Topics, dans l'interface Kafka ou par `kafka/topics.sh` : `mosip.regprc.enrichissement` (compacté) et
   `mosip.regprc.enrichissement.erreurs` (28 jours), une partition chacun.
7. Connecteurs, dans l'interface Kafka : `lake-regprc-enrichissement` et `ods-regprc-enrichissement` (fichiers de
   `kafka/connecteurs/`, mot de passe reporté). Les comparer d'abord à `lake-enrichissement` et `ods-enrichissement`
   des pré-inscriptions, qui lisent des messages de même forme : reprendre tout réglage qui y figure en plus
   (convertisseurs par exemple).
8. Essai limité, sous le verrou du rattrapage (dans `compose/`), à une heure de fin proche :
   `flock /tmp/mosip-rattrapage.lock docker compose run --rm -T spark-batch /opt/spark/bin/spark-submit --master local[2]
   /app/jobs/rattrapage_stock.py --source inscriptions --debit 4 --simultanes 2 --limite 200 --fin <HH:MM>`.
   Attendu : « 200 traités, 200 enrichis » ou presque ; puis, une minute plus tard,
   `select count(*), count(*) filter (where genre is null) from ods.regprc_enrichissement;` et
   `select genre, count(*) from lake.mosip_regprc_enrichissement group by 1;` (Femme, Homme). Un échec
   `KER-ATH-…` ou HTTP 401/403 : identifiants refusés pour l'ID Repository (étape « Avant tout ») ; le
   rattrapage s'arrête alors de lui-même (« l'API refuse l'accès … Arrêt »), après cinq refus d'un jeton tout neuf.
9. Job en continu des NIU : `docker compose up -d spark-stream-inscriptions` ; puis
   `docker compose restart spark-stream` pour que le job des pré-inscriptions charge le code commun mis à jour (même
   point de reprise : il repart où il s'était arrêté). Journal : `docker logs -f mosip-cdc-spark-inscriptions`
   (une ligne par lot : dossiers, enrichis, échecs).
10. Cron : copier `ops/cron/mosip-bi` dans `/etc/cron.d/mosip-bi`. Le rattrapage des NIU passe après celui des
    pré-inscriptions, dans les mêmes créneaux et sous le même verrou (environ 6 M de NIU : 4 à 5 jours aux débits de
    32 et 8 appels/s).
11. Vérifier : `bi.fait_niu_profil_jour` et `bi.fait_niu_nationalite_jour` totalisent les NIU de `bi.fait_niu_jour`
    (le test dbt l'impose) ; la part « Non renseignée » baisse à chaque créneau ; les valeurs de nationalité
    (`select nationalite, sum(niu_generes) from bi.fait_niu_nationalite_jour group by 1 order by 2 desc;`) sont des
    libellés de la liste MOSIP, sinon signaler les valeurs brutes.

Retour arrière : `docker compose stop spark-stream-inscriptions`, retirer ses lignes du cron, supprimer les deux
connecteurs. Le profil reste publié avec les réponses déjà reçues ; revenir au commit précédent de `mosip-cdc` vide
`bi.fait_niu_profil_jour` au passage suivant (la pyramide repasse à 0).

## Exploitation et reprise

| Situation | Action |
|---|---|
| `ref_regprc_statuts.csv` ou `ref_regprc_etapes.csv` modifié | `dbt build --full-refresh --select suivi_inscription+`, puis `scripts/charger-suivi.sh` |
| `ref_regprc_motifs.csv` ou `ref_regprc_stages.csv` modifié | rien pour les blocs et les libellés du suivi : pris en compte au passage suivant (`motif_inscription` recalculée en entier, `bi.ref_motif` republiée) ; si une **règle** (colonne `regle`) range autrement des messages déjà vus : `scripts/rattraper-motif-suivi.sh` pour le motif des dossiers suivis |
| Colonne ajoutée ou retirée dans un seed (`dbt/seeds/*.csv`) | dbt ne modifie pas la table d'un seed : `flock /tmp/mosip-analytique.lock docker compose run --rm -T dbt seed --full-refresh --select <seed>` (dans `compose/`), sinon le passage échoue (« column … does not exist ») et rien n'est publié (incident du 28/10/2026) |
| Alerte « commentaire non répertorié » | ajouter le message (une expression régulière, sans chiffres variables) et sa traduction à `ref_regprc_motifs.csv`, avec une priorité libre ; commiter, `git pull` sur le serveur |
| `dbt --full-refresh` de `suivi_inscription` | `scripts/charger-suivi.sh` (toutes les lignes ont une nouvelle `maj_le`) |
| Clé `SUIVI_HMAC_CLE` changée | mettre la nouvelle clé dans `compose/.env`, puis `scripts/charger-suivi.sh --vider`, puis redémarrer l'API (`docker compose -f docker-compose.dashboard.yml up -d api`, qui relit la clé) |
| Suivi d'un dossier : « n'est pas configuré » (503) | l'API n'a pas reçu `SUIVI_HMAC_CLE` : vérifier `compose/.env` et la ligne `SUIVI_HMAC_CLE` de `docker-compose.dashboard.yml`, puis `up -d api` |
| Suivi d'un dossier : un RID connu de MOSIP « ne correspond à aucun dossier » | dossier pas encore publié (passage suivant du cron) ou clé de l'API différente de celle de la publication |
| Topic recréé ou ODS rechargé (offsets repartis de 0) | `dbt build --full-refresh --select suivi_inscription+`, puis `scripts/charger-suivi.sh` |
| Slot perdu | nouveau slot, nouveau snapshot (l'ODS est réécrit sur place), puis la ligne précédente |
| Connecteur source arrêté plus d'un jour | MOSIP en PostgreSQL 12 ne plafonne pas les journaux retenus : supprimer le slot (DBA), puis nouveau snapshot |
| Alerte « genre de l'ID Repository non reconnu » (`assert_enrolement_genres_inconnus`) | ajouter la valeur à la règle `sexe` de `stg_regprc__enrichissement.sql`, puis `dbt build --full-refresh --select stg_regprc__enrichissement+` (les réponses déjà lues sont relues depuis le lake) |
| Rattrapage ou job en continu : « l'API refuse un jeton tout neuf … plus aucun appel pendant 10 min » | le compte de `IDREPO_*` (à défaut `API_*`) s'authentifie mais n'a pas le droit d'appeler l'ID Repository : demander à l'équipe MOSIP un client autorisé, le mettre dans `compose/.env`, puis `docker compose up -d spark-stream-inscriptions` (relit `.env`). Le client ne se réauthentifie jamais en boucle (essai du 29/10/2026 : 600 authentifications avant cette protection) |
| Profil des NIU : « Non renseignée » qui ne baisse plus | `docker logs mosip-cdc-spark-inscriptions` et `rattrapage.log` ; codes d'échec dans `mosip.regprc.enrichissement.erreurs` (`IDR-IDC-007` : RID inconnu de l'ID Repository, repris à chaque rattrapage) |
| Tout ré-enrichir (règle d'extraction changée) | `truncate ods.regprc_enrichissement` (par `ods_writer`) : le rattrapage rappelle l'ID Repository pour chaque NIU ; le lake garde les anciennes réponses, dbt prend la plus récente |
| Disque `/data` de la BD traitement qui se remplit (archives WAL, `archwal/PGArchives`) | 30/10/2026 : 830 Go de WAL par jour, 97 % de `/data`. Causes : la publication vidait et rechargeait les tables `bi` à chaque passage (`bi.fait_delai_jour` : 1,8 M de lignes, gonflée à 7 Go), et dbt journalisait des tables reconstruites en entier. Corrigé : publication par différences (`sql/publication/synchroniser.sql`), modèles `unlogged`. Mesurer un passage : `select pg_current_wal_lsn()` avant et après, puis `pg_wal_lsn_diff`. La conservation et la purge des archives relèvent du DBA |
| Passage dbt en échec, « tuple concurrently updated » sur un modèle de `dm_enrolement` | deux `GRANT` simultanés sur le schéma (30/10/2026, 4 h 36 à 5 h 11 : rien publié) ; corrigé dans `dbt_project.yml` (le post-hook n'accorde l'usage que s'il manque). S'il revient sur un autre objet : relever le modèle et l'objet, ne pas baisser le nombre de threads sans mesure |
| Alerte « entry_date modifiée » | signaler à l'équipe MOSIP : la date du NIU n'est pas stable pour ces dossiers |
| `suivi_inscription` en échec, « duplicate key value violates unique constraint » | deux liens `rid_uin_link` pour un même RID (rien ne l'interdit dans l'ODS) : `select reg_id, count(*) from ods.regprc_rid_uin_link group by 1 having count(*) > 1;`, signaler à l'équipe MOSIP ; rien n'est publié tant que le doublon reste |

Retour arrière : supprimer la source `mosip-regprc-cdc`, puis le slot côté MOSIP (DBA). Revenir au commit précédent de
`mosip-cdc` ; les tables V7 restent vides et ne gênent pas l'API.

## Banc de test

`outils/banc/README.md` : PostgreSQL jetable, vraies migrations du backend (V1 à V9), vrais scripts de droits et de
publication ; les connecteurs sont simulés par des `insert` dans l'ODS.
