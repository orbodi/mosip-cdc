# Enrôlement : analyse des sources et des indicateurs

> **Remplacée.** Cette version s'appuyait en partie sur le DDL et la documentation officielle de MOSIP. Décision du
> 24/10/2026 : l'analyse ne repose que sur les structures fournies et sur les résultats des requêtes, consignés dans
> `docs/releve-enrolement.md`. Ce fichier sera réécrit à partir du relevé ; d'ici là, ne pas s'y fier.


Date : 24/10/2026. Statut : **à valider** avec l'équipe MOSIP et le responsable du projet, avant de compléter le
pipeline (`docs/enrolement.md`), puis le backend et le front.

## Méthode et limites

Cette analyse croise cinq sources :
- les **structures réelles de l'instance ANID** (`\d` des quatre tables retenues et `\dRp+`, fournis le 24/10/2026 ;
  voir § 0) ;
- les DDL officiels MOSIP v1.1.5 (copiés dans `mosip-bi-reporting/pipeline/sources/ddl/`, branche `main`) ;
- le dictionnaire des indicateurs (`docs/indicateurs.md` de `main`) ;
- la maquette de la page (`maquette/pages/Enrolement.dc.html`) ;
- les chiffres du BI actuel au 14/01/2026, qui servent de référence.

**Aucune donnée réelle n'a été lue, seulement des structures.** Les codes de statut et de transaction, les volumes et
le préfixe RID → centre restent des hypothèses tant que le relevé n'est pas revenu. Le relevé tient en trois scripts,
un par base : `sql/mosip/03_releve_enrolement_regprc.sql`, `_master.sql` et `_idrepo.sql`. Il est en lecture seule et
ne fait que des comptages ; il a été vérifié sur des tables simulées aux DDL officiels. Chaque indicateur ci-dessous
dit quelle réponse du relevé le confirme (R1, R2…).

## 0. Tables retenues et constats sur l'instance (structures du 24/10/2026)

Quatre tables sont retenues : `regprc.registration`, `regprc.registration_transaction`, `regprc.rid_uin_link` et
`regprc.registration_list`.

1. **`rid_uin_link` est propre à l'ANID** (absente du DDL officiel). C'est le lien entre une inscription et son NIU.
   - Colonnes : `id` (entier, clé primaire), `entry_date`, `uin` (le NIU), `reg_id` (RID, **unique**), `reg_type`,
     `civil_registry_number` (numéro d'état civil).
   - Captées : `id`, `reg_id`, `reg_type`, `entry_date`. **Jamais captées** : `uin` et `civil_registry_number`,
     identifiants de personne.
   - La clé primaire est un entier sans valeur métier : la clé des messages Kafka ne porte aucun identifiant.
   - **Conséquence majeure** : si `entry_date` est bien l'heure de génération du NIU (R11), la date exacte de **tout
     l'historique** est connue. On n'a plus besoin d'estimer (option a), ni de demander un agrégat au DBA (option b),
     ni de capter `registration_transaction` pour ça (option c). Le délai médian jusqu'au NIU devient exact, passé
     compris (point 4 du § 3).
   - Pièges :
     - `reg_id` est en `varchar(100)` (39 dans `registration`) : comparer après `trim` (R11) ;
     - un même NIU peut avoir plusieurs lignes (mise à jour, perte) : compter des inscriptions (`reg_id`), jamais des
       NIU distincts.
2. **Une publication existe déjà** sur `mosip_regprc` : `dbz_publication`, propriétaire `enterprisedb`, sans
   « toutes les tables ».
   - Elle couvre `registration`, `registration_list`, `registration_transaction` et `rid_uin_link`, plus quatre tables
     d'impression (`printing_orders`, `printing_orders_details`, `printing_processing_jobs`,
     `printing_shipped_cards`), utiles plus tard pour la page Impression des cartes.
   - Comme `mosip-master-cdc` sur `mosip_master`, le connecteur de l'enrôlement l'utilisera avec son propre slot :
     plus de publication `bi_cdc_regprc` à créer (`02_prerequis_regprc.sql` et le connecteur sont corrigés dans ce sens).
   - **À vérifier** (R12) : `\d regprc.registration` n'affiche pas de ligne « Publications », alors que les trois autres
     tables en ont une.
   - Données personnelles : la publication transmet toutes les colonnes au slot ; Debezium ne garde que
     `column.include.list`, donc `uin` n'entre jamais dans Kafka. Une liste de colonnes dans la publication
     (PostgreSQL 15 et plus) serait plus sûre : version d'EDB à demander au DBA.
3. **`registration`, `registration_transaction` et `registration_list` sont conformes au DDL officiel 1.1.5.** Les
   index ajoutés par l'exploitation montrent comment MOSIP s'en sert :
   - `status_comment = 'Manual verification Sent to queue'` repère la file de vérification manuelle ;
   - `trn_retry_count < 10` et `status_code <> 'REJECTED'` repèrent les candidats au retraitement ;
   - les index `(reg_type, entry_date)` de `rid_uin_link` et `(cr_dtimes, latest_trn_status_code)` de
     `registration` correspondent sans doute aux requêtes du BI actuel (NIU par jour, devenir par jour).
4. **Toutes les dates sont sans fuseau** (`timestamp without time zone`). MOSIP écrit en UTC, qui est l'heure de Lomé.
   R3 le vérifie par les heures d'activité.
5. Tables liées, **jamais captées** : `individual_demographic_dedup` (référence `registration`) et
   `reg_demo_dedupe_list` (référence `registration_transaction`).

## 1. Ce que la page Enrôlement doit montrer (maquette)

| Bloc | Chiffres affichés | Codes |
|---|---|---|
| Pré-inscription | demandes, rendez-vous réservés, en attente, expirées, honorées à l'inscription, femmes pré-inscrites, dernière demande | E-PRE… (chaîne pré-inscriptions, hors de cette analyse) |
| Devenir des inscriptions | NIU générés (nombre et %), en cours **« dont N bloqués depuis plus de 30 jours »**, échoués, rejetés | E-NIU, E-COURS, **E-BLOQ**, E-ECH, E-REJ |
| Inscriptions et NIU par semaine | 12 semaines : inscriptions (jour de réception) et NIU (jour de génération) | E-INS, E-NIU (flux) |
| Territoire | carte colorée par taux de NIU ; cartes Inscriptions, NIU, Taux de rejet, En cours, **Délai médian jusqu'au NIU** ; tableau par région puis préfecture : inscriptions, NIU, rejets (taux, ▲ si ≥ 3,5 %), échoués, en cours, **délai médian** | E-INS, E-NIU, E-REJ, E-ECH, E-COURS, **E-DELAI** |
| NIU générés par âge et par sexe | pyramide, 8 tranches, femmes et hommes | E-NIU-PROFIL |
| Top des centres | 5 centres : plus d'enregistrements, plus d'échecs, plus de rejets | E-INS, E-ECH, E-REJ |

Les indicateurs du dictionnaire absents de la page, comme E-MAJ (mises à jour), E-PERTE (récupérations de NIU) et
E-TRAIT (traités), relèvent de l'Exploration.

## 2. Tables MOSIP candidates

| Base.table | Volume probable | Colonnes utiles | Jamais capturées | Apport |
|---|---|---|---|---|
| `regprc.registration` | 1 ligne par inscription ≈ 3,3 M | `id` (RID), `reg_type`, `status_code`, `latest_trn_type_code`, `latest_trn_status_code`, `latest_trn_dtimes`, `reg_stage_name`, `pkt_cr_dtimes`, `cr_dtimes`, `upd_dtimes`, `is_deleted`, `reg_process_retry_count` | `ref_reg_id`, `applicant_type`, `status_comment`, `cr_by`, `upd_by` | Statut courant, type, étape, dates, centre (et machine) lus dans le RID. **Déjà captée** (lot du 24/10). |
| `regprc.registration_transaction` | 1 ligne par étape franchie ≈ 10 à 20 × 3,3 M (R6) | `reg_id`, `trn_type_code`, `status_code`, `sub_status_code`, `cr_dtimes` | `remarks`, `status_comment` (texte libre), `ref_id` (peut contenir un NIU) | **Date exacte du NIU** (transaction de génération), délai médian exact, étape et motif des rejets, retraitements |
| `regprc.rid_uin_link` (ANID) | 1 ligne par inscription ayant un NIU ≈ 3,1 M (R11) | `id`, `reg_id`, `reg_type`, `entry_date` | **`uin`, `civil_registry_number`** | **Date exacte du NIU, historique compris** ; délai médian exact ; contrôle croisé avec le statut « abouti » |
| `regprc.registration_list` | 1 ligne par paquet synchronisé ≈ 3,3 M | `reg_id`, `reg_type`, `status_code`, `client_status_code`, `packet_size`, `cr_dtimes` | `additional_info`, `*_comment`, `packet_checksum` | Paquets **synchronisés mais non chargés** (sync sans inscription) |
| `regprc.reg_manual_verification` | ≈ 40 000 (AJ-REC du BI actuel : 41 870) | `reg_id`, `status_code`, `reason_code`, `trntyp_code`, `cr_dtimes` | `res_text`, `mv_usr_id` (agent), `matched_ref_id` | Rejets par l'adjudication. Sert surtout la page ABIS. |
| `regprc.transaction_type` | dizaines | `code`, `descr`, `lang_code` | — | Libellés des étapes (référentiel, aucune donnée personnelle) |
| `idrepo.anonymous_profile` | 1 par NIU, mise à jour ou perte (≈ 3,1 M) ; **seulement en MOSIP 1.1.5.5 et plus** (R10) | `profile` JSON, dont on ne tire que processus, date, genre, année de naissance → tranche, lieu → région ; `cr_dtimes` | le JSON lui-même, biométrie, documents | Pyramide âge × sexe, sexe des NIU par région |
| `master.registration_center` | centaines | `id`, `name`, `location_code`, `number_of_kiosks`, `cntrtyp_code`, `latitude`, `longitude`, `is_active` | adresses, contact | Rattachement des centres (déjà capté), postes par centre |
| `master.machine_master` | centaines | `id`, `regcntr_id`, `is_active` | `mac_address`, `serial_num`, `ip_address`, clés | Grain machine (Exploration, décision 8 du data mart) |

À exclure dans tous les cas : `regprc.individual_demographic_dedup` (sexe, mais à côté de données d'identité en clair),
`idrepo.uin*`, documents et biométrie.

## 3. Indicateurs réalisables

Disponibilité :
- **Oui** : calculable avec `registration`, déjà captée ;
- **Approché** : calculable, mais estimé pour l'historique ;
- **Sous condition** : demande une autre table ou une validation ;
- **Non** : pas de source.

| Code | Indicateur | Règle proposée | Source minimale | Disponibilité | Confirmé par |
|---|---|---|---|---|---|
| E-INS | Inscriptions | une ligne de `registration` non supprimée, au jour de `cr_dtimes` | registration | Oui | R2, R3 |
| E-NIU | NIU générés (cohorte) | inscriptions au statut regroupé « abouti » ; ou présence dans `rid_uin_link` (point 7 ci-dessous) | registration, rid_uin_link | Oui, **si la correspondance des statuts est validée** | R2, R11 |
| E-COURS | En cours | statut regroupé « en cours » | registration | Oui | R2 |
| E-BLOQ | Bloqués depuis plus de 30 jours | en cours dont `latest_trn_dtimes` a plus de 30 jours. C'est un **stock à l'instant**, pas un fait par jour. | registration | **Oui** (pas besoin de `registration_transaction`) | R5 |
| E-ECH | Échoués | statut regroupé « échoué » | registration | Oui | R2 |
| E-REJ | Rejetés, taux de rejet | statut regroupé « rejeté » / inscriptions de la zone | registration | Oui | R2 |
| E-TRAIT | Paquets traités | NIU + échoués + rejetés | calcul | Oui | — |
| E-MAJ, E-PERTE | Mises à jour, récupérations | `reg_type` UPDATE (+ RES_UPDATE ?), LOST | registration | Oui | R2 |
| — | NIU par semaine (flux) | NIU au jour de leur génération (`rid_uin_link.entry_date`) | rid_uin_link | **Oui**, exact historique compris, si R11 confirme le sens de `entry_date` | R11 |
| E-DELAI | Délai médian jusqu'au NIU | médiane de (`entry_date` − `cr_dtimes`), par zone et période | registration + rid_uin_link | **Oui**, même condition | R11 |
| — | Taux de NIU (couleur de la carte) | NIU / inscriptions de la zone | registration | Oui | — |
| — | Top des centres | inscriptions, échoués, rejetés par centre | registration + référentiel | Oui, **si le préfixe RID = centre est confirmé** | R4 |
| E-NIU-PROFIL | NIU par âge et par sexe | profils « New » par genre et tranche (année du profil − `yearOfBirth`), par région | anonymous_profile | **Sous condition** : version 1.1.5.5 et plus | R10 |
| — | Synchronisés mais non chargés | `reg_id` de `registration_list` sans ligne dans `registration` (jointure, jamais une différence de totaux) | registration_list | Sous condition (capture d'une table de plus) | R8 |
| — | Rejets par étape et par motif | étape (`trn_type_code`) de la transaction de rejet ; motif via `sub_status_code` ou `reason_code` | registration_transaction, reg_manual_verification | Sous condition (+ correspondance des motifs à valider) | R6, R9 |

### Points qui changent les chiffres (à trancher avec le relevé)

1. **Quel statut regrouper ?**
   - `status_code` donne l'état global du paquet ; `latest_trn_status_code`, celui de la dernière étape.
   - Le BI actuel mélange les deux, d'où ses « statuts en doublon ».
   - Proposition : regrouper `status_code` seul, et ne garder `latest_trn_*` que pour l'étape et le blocage.
   - Le croisement R2 montre si c'est cohérent.
2. **Jour d'une inscription : `cr_dtimes` (réception par MOSIP) ou `pkt_cr_dtimes` (création du paquet au centre) ?**
   - L'écart entre les deux correspond au délai de remontée des centres (R3).
   - S'il est souvent de plusieurs jours, les semaines « récentes » paraîtront creuses avec `cr_dtimes`.
   - Proposition : garder `cr_dtimes` comme jour officiel, et publier ce délai comme indicateur (§ 4).
3. **NIU générés : tous types ou NEW seulement ?**
   - Une mise à jour (UPDATE) ou une perte (LOST) aboutie ne crée pas de NIU.
   - Proposition : « NIU générés » = abouties de type NEW. Les autres types aboutis comptent en « traitées », visibles
     dans l'Exploration.
   - Cela change le contrat actuel, où `niu_generes` compte tous les types, ainsi que l'égalité de contrôle du backend.
     Ce n'est pas anodin (≈ 1 % des inscriptions d'après le BI actuel).
4. **Date du NIU pour l'historique.**
   - Sans `registration_transaction`, une inscription déjà aboutie avant le début de la capture reçoit une date estimée
     (`latest_trn_dtimes`, c'est-à-dire la dernière étape franchie, souvent l'impression, après le NIU).
   - Comme tout l'historique précède la capture, la courbe des NIU et le délai médian seraient faux pour le passé,
     jusqu'à ce que le passé sorte de la fenêtre de 12 semaines.
   - Trois options, à trancher :

   | Option | Ce qu'on fait | Coût | Précision |
   |---|---|---|---|
   | a. Estimation | rien de plus (lot actuel) | nul | historique approché, futur exact |
   | b. Agrégat historique ponctuel | le DBA exécute une fois une requête de comptage (NIU par jour × centre × type depuis `registration_transaction`) ; résultat chargé comme table de reprise | faible, aucune donnée personnelle | historique exact, futur exact par la capture ; délai médian historique par histogramme agrégé |
   | c. Capture de `registration_transaction` | connecteur sur la table, colonnes sans texte libre ni `ref_id` | 30 à 60 M lignes au snapshot (R6), lake plus lourd | tout exact ; ouvre les motifs de rejet et les étapes |

   **Point dépassé** depuis la découverte de `rid_uin_link` (§ 0). Si R11 confirme que `entry_date` est l'heure de
   génération du NIU, on capte `rid_uin_link`, et a, b et c deviennent inutiles pour la date du NIU. L'option c ne
   servirait plus qu'aux rejets par étape et par motif (phase 2). Si R11 l'infirme, on revient au choix précédent
   (recommandation : b).
5. **Préfixe RID → centre** (R4). Si les 5 premiers chiffres ne retrouvent pas les identifiants de
   `master.registration_center`, tout le territoire tombe dans « Centre non référencé ». Il faudrait alors un autre
   lien (`registration_list` ? machine ?).
6. **Bloqué** : « dernière transaction de plus de 30 jours » est la règle du dictionnaire. Le relevé (R5) donne la
   répartition par ancienneté et par étape. Référence du BI actuel : 118 402 bloqués sur 123 639 en cours, soit 96 %.
   C'est donc presque tout le stock : à faire confirmer.
7. **Qu'est-ce qu'un NIU généré : statut « abouti » ou ligne dans `rid_uin_link` ?** Les deux devraient coïncider pour
   les inscriptions NEW (R11 les croise).
   - Proposition : le **Devenir** garde le statut regroupé, pour que l'égalité NIU + en cours + échoués + rejetés =
     inscriptions tienne.
   - La **date** du NIU vient de `rid_uin_link`.
   - L'écart entre les deux comptages est affiché en contrôle et consigné, jamais corrigé.
   - À trancher avec l'équipe MOSIP : qui écrit `rid_uin_link`, à quel moment, depuis quand ; sens de `reg_type` ;
     cas des UPDATE et LOST.
8. **`applicant_type`** (citoyen, étranger… ?) est exclue par prudence. Si R2 montre une catégorie simple et non
   identifiante, ce serait une ventilation utile. À décider.

## 4. Indicateurs proposés en plus (tous calculables avec `registration`)

| Proposition | Règle | Intérêt | Où l'afficher |
|---|---|---|---|
| En cours par étape | stock des en cours par `reg_stage_name` (ou `latest_trn_type_code`) et ancienneté (< 7 j, 7-30 j, > 30 j) | dit **où** les dossiers bloquent (déduplication, vérification manuelle…) | bulle du Devenir ou Exploration |
| Délai de remontée des paquets | médiane de `cr_dtimes − pkt_cr_dtimes` par centre | repère les centres qui synchronisent tard (connexion, logistique) | Territoire, Top des centres |
| Centres actifs | centres avec au moins une inscription reçue sur la période ; inscriptions par poste (`number_of_kiosks`) | activité et productivité du réseau | Exploration |
| Retraitements | inscriptions avec `reg_process_retry_count > 0` | charge de reprise du traitement | Exploration |
| Grain machine | chiffres 6 à 10 du RID | activité par poste d'enrôlement | Exploration (décision 8) |

## 5. Plan proposé

| Étape | Pipeline (`mosip-cdc`) | Backend (`mosip-bi-reporting`) | Front |
|---|---|---|---|
| E1. Relevé | DBA : `sql/mosip/03_releve_enrolement_*.sql` (trois bases) ; ajuster `ref_regprc_statuts.csv` et les règles 1 à 3 | — | — |
| E2. Registration complète | lot du 24/10 (déjà écrit) + modèle « stock des en cours » (étape × ancienneté × centre, recalculé toutes les 5 min) + délai de remontée | migration V7 : `bi.stock_enrolement_courant` (centre × étape × tranche d'ancienneté) ; `devenir` renvoie `bloques` ; si la règle 3 change, `niu_generes` = NEW seul | Devenir : « dont N bloqués depuis plus de 30 jours » ; bulle des étapes si retenue |
| E3. Date du NIU et délai médian | capture de `rid_uin_link` (sans `uin` ni `civil_registry_number`), qui remplace l'estimation du lot du 24/10 (`stg_regprc__niu`) ; modèle `fait_delai_niu_jour` = histogramme (jour × centre × délai en jours → nombre), additif, d'où une médiane exacte pour toute zone et toute période | migration : `bi.fait_delai_niu_jour` ; `territoire` renvoie `delaiMedian` par ligne et pour la zone | Territoire : carte « Délai médian » et colonne du tableau (aujourd'hui « – ») |
| E4. Âge et sexe | si R10 = oui : connecteur `idrepo.anonymous_profile` et modèle → `bi.fait_niu_profil_jour` (table déjà au contrat V4) | aucun changement (`/age-sexe` existe) | aucun (pyramide prête) |
| E5. Synchronisation, rejets par motif | `registration_list` ; `registration_transaction` si option c | faits et API correspondants | Exploration |

Chaque étape garde les égalités de contrôle (somme des statuts = inscriptions ; NIU flux = NIU cohorte ; territoire =
national) et un scénario de plus dans `outils/banc/`.

## 6. Ce que chaque réponse du relevé décide

| Réponse | Requête | Décide |
|---|---|---|
| R1 | volumes et tailles des tables | faisabilité des captures (surtout `registration_transaction`) |
| R2 | `status_code` × `latest_trn_type_code` × `latest_trn_status_code`, `reg_type` | correspondance des statuts, règles 1 et 3 |
| R3 | bornes des dates, écart `cr_dtimes − pkt_cr_dtimes`, heures d'activité | règle 2, fuseau horaire |
| R4 | préfixes RID (5 et 10 chiffres), longueur du RID | rattachement aux centres, grain machine |
| R5 | ancienneté des en cours par étape | E-BLOQ, stock par étape |
| R6 | transactions par type et statut, transactions par inscription | option c, codes de la transaction « NIU généré » |
| R7 | délai réception → transaction de génération du NIU, inscriptions abouties sans cette transaction | E-DELAI, option b |
| R8 | `registration_list` ↔ `registration` | synchronisés non chargés |
| R9 | adjudication : statut × motif | rejets par motif |
| R10 | existence et contenu (clés, genres, processus) de `idrepo.anonymous_profile` | E-NIU-PROFIL |
| R11 | `rid_uin_link` : types, bornes, liens orphelins, croisement avec le statut et avec la transaction de génération du NIU, délai `entry_date − cr_dtimes` | sens de `entry_date`, points 4 et 7, E-DELAI |
| R12 | tables de `dbz_publication`, replica identity, version du serveur | réutilisation de la publication, liste de colonnes |
