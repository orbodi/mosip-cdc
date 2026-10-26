# Conception du pipeline de l'enrôlement : proposition (25/10/2026, à valider)

Fondée sur `docs/releve-enrolement.md` (relevé des étapes 1 à 6) et sur le catalogue v2 (I1 à I11). Elle remplace le
lot écrit le 24/10 (`dwh/regprc`, `dm_enrolement`), conçu avant le relevé. Ce lot reste un brouillon à réécrire.

## 1. Principes tirés du relevé

- **Aucune suppression** dans les sources : la capture ne gère que des créations et des modifications.
- **`registration` reçoit environ 610 000 mises à jour par jour** : on garde un **état courant** (ODS, une ligne par
  inscription, mise à jour sur place), pas un journal de chaque événement.
- **`registration_transaction` est en ajout seul (environ 676 000 lignes par jour, 206 Go d'historique)** : on la
  capte **sans snapshot**, seulement les nouvelles lignes, en phase 2.
- **`rid_uin_link` est modifiée après insertion** sans qu'on sache quelles colonnes : on garde son journal (lake),
  assez léger (environ 35 000 événements par jour), pour mesurer tout changement d'`entry_date`.
- **Même patron que les pré-inscriptions** : Debezium (slot `mosip_regprc_cdc`, publication `dbz_publication`
  existante), connecteurs JDBC vers l'ODS ou le lake, dbt toutes les 5 minutes, publication vers `bi` dans une seule
  transaction.

## 2. Capture

| Table | Colonnes captées | Snapshot | Destination | Volume courant |
|---|---|---|---|---|
| `registration` | `id`, `reg_type`, `status_code`, `latest_trn_type_code`, `latest_trn_status_code`, `latest_trn_dtimes`, `reg_stage_name`, `cr_dtimes`, `upd_dtimes` | oui (6,4 M lignes) | `ods.registration` (upsert sur `id`) | ≈ 620 000 événements par jour |
| `rid_uin_link` | `id`, `reg_id`, `reg_type`, `entry_date` (**jamais** `uin` ni `civil_registry_number`) | oui (6,0 M) | `ods.rid_uin_link` (upsert) **et** `lake.mosip_regprc_rid_uin_link` (journal) | ≈ 35 000 par jour |
| `registration_list` | `id`, `reg_id`, `reg_type`, `client_status_code`, `cr_dtimes`, `upd_dtimes` | oui (6,4 M) | `ods.registration_list` (upsert) | ≈ 26 000 par jour |
| `registration_transaction` (phase 2) | `id`, `reg_id`, `trn_type_code`, `status_code`, `sub_status_code`, `cr_dtimes` | **non** (nouvelles lignes seulement) | `lake.mosip_regprc_registration_transaction`, partitionnée par mois | ≈ 676 000 par jour |

Colonnes écartées parce que le relevé les montre vides ou constantes : `pkt_cr_dtimes`, `applicant_type`,
`lang_code`, `is_active`, `is_deleted` (registration) ; `status_code`, `is_deleted` (registration_list).

**Enrichissement démographique** (âge, genre, nationalité), sur le modèle des pré-inscriptions :
- un job Spark appelle l'API MOSIP pour chaque inscription ;
- il ne garde que le genre, l'année et le mois de naissance et la nationalité ;
- il publie dans un topic, puis `lake` / `ods.enrichissement_inscription` ;
- en continu pour les nouvelles inscriptions, plus un rattrapage du stock (≈ 6 M dossiers, environ 5 jours aux débits
  des pré-inscriptions : 32 appels/s la nuit, 8 le jour).

**À préciser** : quelle API et quel point d'accès, avec le RID en entrée.

## 3. Data warehouse (dbt, toutes les 5 minutes)

- `dwh.suivi_inscription` : **une ligne par inscription**, la table pivot. Colonnes :
  - RID, centre (5 chiffres), poste (10 chiffres), type ;
  - jalons : `enrole_le` (horodatage du RID), `synchronise_le` (première synchronisation), `refus_poste` (client
    REJECTED), `recu_le` (`cr_dtimes`), `niu_le` (`entry_date`) ;
  - `status_code`, `etape` (`latest_trn_type_code`), `derniere_trn_le` ;
  - `devenir` (règle I4 : `niu` si lien, sinon `en_cours` pour PROCESSING ou ERROR, `echouee` pour FAILED ou
    PACKET_UPLOADER_FAILED, `rejetee` pour REJECTED) ;
  - genre, tranche d'âge et nationalité (enrichissement).
- Seeds de libellés : étapes (`latest_trn_type_code` → libellé français, et VALIDATE_PACKET = « Refus au poste » quand
  la synchronisation est REJECTED), statuts, tranches de délai.
- Faits du data mart, calculés depuis `dwh.suivi_inscription` : voir § 4.

## 4. Contrat `bi` (migration V7 du backend, en ajout)

| Table `bi` | Grain | Mesures | Indicateurs |
|---|---|---|---|
| `fait_enrolement_jour` (existante) | jour de réception × centre × sexe × tranche × type | inscriptions, NIU (= avec lien), en cours, échouées, rejetées | I1, I2 cohorte, I4, I5 total |
| `fait_niu_jour` (existante) | jour du NIU × centre × type | NIU | I2 flux, I3 |
| **`fait_arret_etape_jour`** | jour de réception × centre × type × devenir (rejetée, échouée) × étape | inscriptions | I5, I6 par étape |
| **`stock_en_cours`** | centre × étape × ancienneté (< 7 j, 7 à 30 j, > 30 j) | inscriptions | I7, « dont bloqués » |
| **`fait_delai_jour`** | jour × centre × mesure (réception → NIU, enrôlement → réception) × classe de délai (heure par heure jusqu'à 48 h, puis jour par jour) | inscriptions | I8, I9 : la médiane et le 90e centile se calculent pour toute zone et toute période en additionnant les histogrammes |
| **`stock_synchro_non_recue`** | centre × ancienneté | paquets | I10 |
| **`suivi_dossier`** | une ligne par inscription, clé = **empreinte HMAC du RID** (jamais le RID) | centre, type, jalons, statut, étape, dernière transaction, devenir | I11 |
| `fait_niu_profil_jour` (existante) | jour du NIU × région × sexe × tranche | NIU | profil (enrichissement) |
| **`fait_niu_nationalite_jour`** | jour du NIU × région × nationalité | NIU | profil (enrichissement) |

L'empreinte du RID est calculée **à la publication** (`pgcrypto`, `hmac(rid, clé, 'sha256')`), avec la clé `SUIVI_HMAC_CLE` du fichier
`compose/.env` (non versionné, mode 600 ; décision du 25/10/2026), passée au script dans une variable, jamais écrite
dans le dépôt ni dans les journaux. L'API la recalcule avec la même clé pour la
recherche.

## 5. API et front (aperçu)

- **Nouvelles routes** :
  - `GET /enrolement/etapes` (rejets et échecs par étape) ;
  - `GET /enrolement/en-cours` (stock par étape et ancienneté) ;
  - `GET /enrolement/delais` ;
  - `GET /enrolement/synchronisation` ;
  - `GET /enrolement/profil` (âge, sexe, nationalité) ;
  - `POST /enrolement/suivi` : RID dans le corps de la requête, journal applicatif des recherches. Sans plafond de
    recherches (décision du 26/10/2026) ni portée régionale (chaque utilisateur a accès à tout le Togo, décision du
    25/10/2026).
- **Routes existantes à ajuster** :
  - `devenir` : règle I4 ;
  - `territoire` : délai médian ;
  - `centres` : onglet « Remontée la plus lente ».
- **Front** : maquette proposée en conversation le 25/10/2026, refaite à partir de la branche `dashboard` (le front et
  le backend à jour y sont).
  - **Bandeau** : sans filtres, avec le lien vers l'Exploration et un nouveau bouton « Suivre un dossier ».
  - **Inchangés** : Pré-inscription, Profil des pré-inscrits.
  - **Modifiés** :
    - Devenir (règle I4, « dont N bloqués ») ;
    - Inscriptions et NIU par semaine (NIU à leur date exacte) ;
    - Territoire (délai médian, étape dominante de l'alerte de rejet) ;
    - Profil des NIU générés (âge, sexe, nationalité, mise en page du profil des pré-inscrits) ;
    - Top des centres (onglet « Remontée la plus lente »).
  - **Nouveaux** : Suivi d'un dossier, Où s'arrêtent les dossiers, trois cartes de délai.

## 6. Contrôles (dbt, bloquants sauf mention)

- **I4** : NIU + en cours + échouées + rejetées = inscriptions, par jour et centre.
- **NIU** : NIU par jour du NIU = NIU par jour de réception, sur toute la durée.
- **Complétude** : `suivi_dossier` a autant de lignes que l'ODS `registration`.
- **`entry_date`** : nombre de liens dont `entry_date` a changé (journal du lake). **Alerte**, pas un blocage.
- **Centre** : préfixe de RID absent du référentiel. **Alerte**, compté sous « Centre non référencé ».

## 7. Phases

1. `registration`, `rid_uin_link`, `registration_list` : I1 à I10, et I11 en jalons.
2. Enrichissement démographique : profil âge, sexe et nationalité.
3. `registration_transaction` sans snapshot : étapes franchies dans le suivi d'un dossier, durée de chaque étape.
4. Impression et remise (tables `printing_*`) : jalons du suivi, page Impression des cartes.
