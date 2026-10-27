# Relevé de l'enrôlement sur l'instance ANID (mosip_regprc)

Ce document est la seule base de l'analyse de l'enrôlement. Il ne contient que les **structures fournies** (`\d`,
24/10/2026) et les **résultats des requêtes** exécutées par le responsable, étape par étape. Rien n'y vient du DDL ni
de la documentation officielle de MOSIP (décision du 24/10/2026).

Les requêtes sont en lecture seule et ne renvoient que des comptages et des dates : aucun RID, NIU ni numéro d'état
civil.

## Étape 1 (24/10/2026, vers 21 h) : volumes, dates, clés

| Table | Lignes | Taille | Constats |
|---|---|---|---|
| `registration` | 6 360 335 (l'estimation `reltuples` de 7,58 M est fausse : statistiques périmées) | 19 Go | voir ci-dessous |
| `rid_uin_link` | 6 021 772 | 4,9 Go | voir ci-dessous |
| `registration_list` | ≈ 6,17 M (estimation) | 4,0 Go | **requête 1.4 pas encore exécutée** |
| `registration_transaction` | ≈ 280 M (estimation) | **206 Go** | parcours complet trop long (requête coupée) : analyser par échantillon et par index ; un snapshot Debezium complet est exclu |

`registration` :
- `id` est unique et fait toujours 29 caractères ;
- `cr_dtimes` va du 24/11/2023 21:43 au 24/10/2026 20:37 : la table est alimentée en continu ;
- **`pkt_cr_dtimes` est nulle sur 100 % des lignes** : inutilisable, donc le jour d'une inscription = `cr_dtimes` ;
- `latest_trn_dtimes` n'est jamais nulle ;
- `is_deleted` n'est jamais vrai et `is_active` jamais faux : inutiles pour filtrer.

`rid_uin_link` :
- 6 021 772 lignes, `reg_id` unique, jamais nul, toujours 29 caractères ;
- `entry_date` n'est jamais nulle, du 28/11/2023 23:19 au 24/10/2026 20:42 : alimentée en continu ;
- `uin` est nul sur 152 lignes. Les 6 021 620 lignes avec NIU portent 6 000 610 NIU distincts, donc 21 010 lignes
  réutilisent un NIU existant ;
- 968 262 lignes (16 %) ont un `civil_registry_number` ;
- **`id` va de 1 à 183 078 025 pour 6 M de lignes** : la séquence saute, ou des lignes sont supprimées puis
  réinsérées. À éclaircir avant la capture.

Les dates s'affichent au format `24-NOV-23` (compatibilité Oracle d'EDB) : formater avec `to_char` dans les requêtes.

## Étape 2 (24/10/2026, 21 h 30) : codes de `registration`

**Types de demande** (`reg_type`) :

| Type | Inscriptions |
|---|---|
| NEW | 6 333 735 (99,6 %) |
| UPDATE | 21 488 |
| LOST | 5 171 |
| RES_UPDATE | 4 |

**Six statuts** (`status_code`) : PROCESSED, PROCESSING, FAILED, REJECTED, PACKET_UPLOADER_FAILED, ERROR.

| Statut | NEW | UPDATE | LOST | RES_UPDATE |
|---|---|---|---|---|
| PROCESSED | 6 000 253 | 19 399 | 1 611 | |
| REJECTED | 156 716 | 715 | 215 | |
| FAILED | 106 051 | 1 220 | 404 | |
| PROCESSING | 69 029 | 134 | 2 939 | 4 |
| PACKET_UPLOADER_FAILED | 1 248 | 20 | 2 | |
| ERROR | 438 | | | |

**`latest_trn_status_code` n'est pas le statut de l'inscription.** Une inscription REJECTED a presque toujours une
dernière transaction FAILED, et une inscription PROCESSING une dernière transaction SUCCESS. C'est la cause des
« statuts en double » du BI actuel. Règle : le statut vient de `status_code` seul. Le couple `latest_trn_type_code` ×
`latest_trn_status_code` dit **à quelle étape** l'inscription s'est arrêtée.

Étape de l'arrêt, par statut (requête 2.2) :

| Statut | Étape (`latest_trn_type_code`) | Inscriptions |
|---|---|---|
| PROCESSED | PRINT_SERVICE | 3 421 769 |
| PROCESSED | UIN_GENERATOR | 2 599 500 |
| PROCESSING | MANUAL_VERIFICATION (SUCCESS 51 733, REPROCESS 6 777, ERROR 69) | 58 579 |
| PROCESSING | PACKET_RECEIVER | 12 186 |
| PROCESSING | autres (FMS, BIOGRAPHIC_VERIFICATION, UPLOAD_PACKET…) | ≈ 1 300 |
| FAILED | **OSI_VALIDATE** | **100 987** |
| FAILED | UPLOAD_PACKET (ERROR, PROCESSING, FAILED) | 5 783 |
| FAILED | autres | ≈ 900 |
| REJECTED | **VALIDATE_PACKET** | **90 477** |
| REJECTED | **DEMOGRAPHIC_VERIFICATION** | **37 523** |
| REJECTED | **MANUAL_VERIFICATION** | **27 679** |
| REJECTED | UIN_GENERATOR | 1 220 |
| REJECTED | autres | ≈ 750 |
| PACKET_UPLOADER_FAILED | UPLOAD_PACKET | 1 270 |
| ERROR | UIN_GENERATOR / IN_PROGRESS | 447 |

`reg_stage_name` concorde avec `latest_trn_type_code` (`PrintingStage`, `UinGeneratorStage`, `OSIValidatorStage`…),
avec deux écarts :
- les 52 148 PROCESSING de `BioDedupeStage` correspondent aux ≈ 51 733 dont la dernière transaction est
  MANUAL_VERIFICATION : ce sont des **inscriptions en attente de vérification manuelle** ;
- 4 lignes ont `reg_stage_name = 'VALIDATE_PACKET'` (un code de transaction) : anomalie de la source.

`applicant_type` est toujours nulle et `lang_code` vaut toujours `eng` : inutiles.

**Rythme** : l'enrôlement avance par campagnes.
- Pics mensuels à 600 000 (2025-05, 2025-06, 2026-04, 2026-09).
- Mois presque vides : 2024-01 à 2024-10, 2025-03, 2025-04, 2025-07, 2025-10, 2026-05 (1 138).

**Croisements qui concordent déjà** :
- PROCESSED, tous types = 6 021 263, à comparer aux 6 021 772 lignes de `rid_uin_link` (écart 509 à expliquer :
  ERROR / UIN_GENERATOR / IN_PROGRESS = 447 ? requêtes lancées à quelques minutes d'écart ?).
- NIU réutilisés dans `rid_uin_link` = 21 010 = UPDATE PROCESSED (19 399) + LOST PROCESSED (1 611), au chiffre près.
  Hypothèse : `rid_uin_link` a une ligne par inscription PROCESSED de tout type ; une UPDATE ou une LOST reprend le NIU
  de la NEW. Donc **nouveaux NIU = NEW**. À confirmer à l'étape 3 (`reg_type` de `rid_uin_link`).

**BI actuel : pas une référence.** Ses chiffres (3 278 239 inscriptions, 3 058 886 NIU, 86 496 rejets…) sont des
**données de test** (précision du responsable, 24/10/2026). Ils ne servent à rien pour valider : les seules
références sont les résultats de ce relevé. Il en va de même pour les « anomalies du BI actuel » de `docs/decisions.md`
et `docs/indicateurs.md` (branche `main`) : statuts en double, −16 734 synchronisés non chargés, etc.

## Étape 3 (24/10/2026, vers 21 h 45) : `rid_uin_link` croisée avec `registration`

**Types de lien** (3.1) :

| Type | Liens | Sans NIU | Premier | Dernier |
|---|---|---|---|---|
| NEW | 6 001 364 | 152 | 2023-11-28 23:19 | 2026-10-24 21:39 |
| UPDATE | 19 399 | 0 | 2023-12-16 22:16 | 2026-10-24 18:46 |
| LOST | 1 611 | 0 | 2024-04-03 14:05 | 2026-10-05 12:09 |

Recoupement avec l'étape 1 : les NIU réutilisés (21 010) sont exactement les liens UPDATE et LOST. Les liens NEW ont
chacun un NIU distinct. **Seule une inscription NEW crée un NIU** ; une UPDATE ou une LOST reprend celui de la
personne. Entre l'étape 1 et l'étape 3, la table a gagné 602 liens (activité en cours).

**Chaque inscription a-t-elle un lien ?** (3.2) :

| Inscription | Statut | Avec lien | Sans lien |
|---|---|---|---|
| NEW | PROCESSED | 6 000 342 (toutes) | 0 |
| NEW | ERROR | **631 (toutes)** | 0 |
| NEW | PROCESSING | 383 | 68 364 |
| NEW | FAILED | 8 | 106 054 |
| NEW | REJECTED, PACKET_UPLOADER_FAILED | 0 | 157 968 |
| UPDATE, LOST | PROCESSED | toutes (19 399 et 1 611) | 0 |
| UPDATE, LOST, RES_UPDATE | autres statuts | 0 | toutes |

- **Aucun lien orphelin** (3.3) : tout `reg_id` de `rid_uin_link` existe dans `registration`.
- **Toute inscription PROCESSED a un lien, et aucune REJECTED ni PACKET_UPLOADER_FAILED n'en a.**
- 1 022 inscriptions NEW ont déjà un NIU sans être PROCESSED : ERROR (631, toutes), PROCESSING (383), FAILED (8).
  Leur NIU est généré mais le traitement n'est pas terminé.
- **Vigilance** : les ERROR (dernière transaction UIN_GENERATOR / IN_PROGRESS) passent de 438 à l'étape 2 à 631 à
  l'étape 3, en 30 minutes environ. Soit c'est un état de passage normal pendant le traitement, soit des dossiers
  restent coincés à la génération du NIU. À suivre (étape 4).

**`entry_date` = heure de génération du NIU** (3.4), pour les PROCESSED :

| Dernière étape | `entry_date` par rapport à `latest_trn_dtimes` | Inscriptions |
|---|---|---|
| UIN_GENERATOR | dans l'heure avant | **2 599 554 (100 %)** |
| PRINT_SERVICE | dans l'heure avant | 2 788 574 (81,5 %) |
| PRINT_SERVICE | 1 h à 1 jour avant | 551 677 |
| PRINT_SERVICE | plus d'un jour avant | 63 844 |
| PRINT_SERVICE | après (dans l'heure : 17 544 ; au-delà : 130) | 17 674 |

Quand la dernière étape est la génération du NIU, `entry_date` tombe toujours dans l'heure qui la précède. Quand
c'est l'impression, `entry_date` la précède presque toujours. **`entry_date` est donc bien la date du NIU**, exacte pour
tout l'historique depuis novembre 2023.

**Délai réception → NIU** (3.5, `entry_date − cr_dtimes`) :

| Type | Liens | Médiane | 90e centile | Maximum | Délai négatif |
|---|---|---|---|---|---|
| NEW | 6 001 364 | 0,35 j (8 h 24) | 10,24 j | 796,6 j | 1 |
| UPDATE | 19 399 | 0,26 j | 7,98 j | 338,1 j | 0 |
| LOST | 1 611 | 0,01 j | 64,24 j | 455,8 j | 0 |

**Les `id`** (3.6) croissent avec le temps : chaque tranche de 9,15 M d'`id` couvre une période plus récente que la
précédente. Mais la séquence est consommée par rafales sans lignes. Par exemple, de 9,1 M à 82 M (3 au 22/07/2025),
environ 73 M d'`id` donnent moins de 20 000 lignes ; de même en octobre-novembre 2025 et en octobre 2026.
Interprétation probable : des tentatives d'insertion qui échouent en masse (doublon sur `reg_id` unique ?) et
consomment la séquence sans laisser de ligne. Une insertion annulée ne produit aucun événement de capture. Les
suppressions restent à mesurer (étape 4, `pg_stat_user_tables`).

## Étape 4 (24/10/2026, vers 23 h) : écritures, synchronisation, statut ERROR

**Activité d'écriture** (4.0), du 01/08/2026 01:40 au 24/10/2026, soit environ 85 jours :

| Table | Insertions | Mises à jour | Suppressions | Par jour (environ) |
|---|---|---|---|---|
| `registration` | 880 491 | **51 821 938** | 0 | 10 000 insertions, **610 000 mises à jour** (≈ 59 par inscription) |
| `registration_list` | 881 180 | 1 343 063 | 0 | 10 000 insertions, 16 000 mises à jour |
| `registration_transaction` | 57 487 972 | **0** | 0 | 676 000 insertions : **table en ajout seul** (≈ 65 transactions par inscription) |
| `rid_uin_link` | 847 979 | **2 170 007** | 0 | 10 000 insertions, 25 500 mises à jour (≈ 2,5 par lien) |

- **Aucune suppression** dans les quatre tables. Les trous de la séquence de `rid_uin_link` viennent d'insertions
  annulées, pas de suppressions.
- **`rid_uin_link` est modifiée après insertion**, environ 2,5 fois par ligne. La table n'a pas de date de
  modification, donc on ne sait pas quelle colonne change (`civil_registry_number` ? `uin` ? `entry_date` ?).
  **Question pour l'équipe** : quel processus met à jour `rid_uin_link`, et quelles colonnes ? Si `entry_date`
  bouge, la date du NIU n'est pas stable.
- **Volume de capture** : `registration` produirait environ 610 000 événements par jour, soit 220 millions par an.
  Garder chaque événement dans le lake, comme pour les pré-inscriptions, est trop lourd pour cette table. Il faudra
  préférer un état courant (upsert) et ne garder que les changements de statut.

**`registration_list`** (4.1 à 4.5) :
- 6 362 660 lignes pour 6 361 436 `reg_id` distincts : 1 224 inscriptions sont synchronisées deux fois, jamais plus ;
- dates du 24/11/2023 21:43 au 24/10/2026 21:41 ; `upd_dtimes` jamais nulle ; `is_deleted` jamais vrai ; `reg_id`
  de 29 caractères ;
- **`status_code` est toujours nulle**. Seul `client_status_code` est renseigné : APPROVED (6 272 218) ou REJECTED
  (90 442) ;
- **recoupement à vérifier** : les 90 442 synchronisations REJECTED côté client sont très proches des 90 477
  inscriptions REJECTED à l'étape VALIDATE_PACKET (étape 2). Hypothèse : un paquet refusé au poste d'enrôlement est
  envoyé quand même, puis rejeté à la validation ;
- **aucune inscription reçue sans synchronisation** ; environ 1 000 synchronisées pas encore reçues (6 361 436
  contre 6 360 418). Leur ancienneté reste à voir (requête 4.4 par mois, pas encore exécutée) ;
- délai synchronisation → réception : médiane 0,06 h (≈ 4 min), 90e centile 3,4 h, maximum 1 289 h (54 jours) ;
  jamais de réception avant la synchronisation.

**ERROR** (4.6) : 219 inscriptions, toutes reçues le jour même et dont la dernière transaction est du jour même. **C'est
un état de passage pendant la génération du NIU**, pas un blocage (438 et 631 aux étapes 2 et 3 : le nombre varie avec
l'activité). À classer « en cours » pour le Devenir.

## Étape 5 (24/10/2026, vers 23 h 45) : derniers croisements

**Synchronisés non reçus, par mois** (5.1) : 1 018 au total.
- 513 datent d'octobre 2026, donc sont probablement en transit.
- Les autres sont anciens, de 2025-01 à 2026-09 (dont 184 en 2025-06 et 119 en 2025-04) : ces paquets ont été
  synchronisés mais **ne sont jamais arrivés**.

**Les rejets « VALIDATE_PACKET » sont des refus au poste d'enrôlement** (5.2). Sur les synchronisations refusées par le
client (`client_status_code = REJECTED`), 90 133 inscriptions finissent REJECTED à VALIDATE_PACKET. Sur les
synchronisations approuvées, il n'y en a que 394. Le rejet est donc décidé au poste (par le superviseur ?), et la
validation ne fait que l'enregistrer. Les rejets se répartissent ainsi :

| Origine | Étape | Inscriptions |
|---|---|---|
| refus au poste | VALIDATE_PACKET (client REJECTED) | 90 133 |
| traitement | DEMOGRAPHIC_VERIFICATION | 37 541 |
| traitement | MANUAL_VERIFICATION | 27 679 (+ 1 avec refus au poste) |
| traitement | UIN_GENERATOR | 1 225 |
| traitement | autres | ≈ 1 100 |

**Ancienneté des inscriptions non terminées** (5.3) :

| Statut, étape | Inscriptions | Dernière transaction > 30 j | Plus ancienne |
|---|---|---|---|
| PROCESSING, MANUAL_VERIFICATION | **58 598** | **56 347 (96 %)** | 2026-07-05 |
| PROCESSING, PACKET_RECEIVER | 7 476 | 0 (2 252 > 7 j) | 2026-10-07 |
| PROCESSING, BIOGRAPHIC_VERIFICATION | 1 822 | 308 | 2025-05-29 |
| PROCESSING, UPLOAD_PACKET | 479 | 303 | 2024-12-19 |
| PROCESSING, FMS | 499 | 0 | 2026-10-24 |
| ERROR, UIN_GENERATOR | 147 | 0 | 2026-10-24 |
| PROCESSING, autres | ≈ 300 | ≈ 130 | 2024-12-17 |

- En tout, environ **57 100 inscriptions sont bloquées depuis plus de 30 jours**, dont 56 347 dans la file de
  vérification manuelle. Cette file n'avance plus : aucune transaction depuis plus de 30 jours pour 96 % des dossiers.
- PACKET_RECEIVER est passé de 12 186 (étape 2) à 7 476 : ces dossiers avancent.

**Structure du RID** (5.4) :
- 29 chiffres partout, jamais d'autre caractère ;
- 3 543 préfixes distincts à 5 chiffres, 8 482 à 10 chiffres ;
- **les 14 derniers chiffres sont un horodatage AAAAMMJJHHMISS**, toujours le jour de la réception ou avant :
  5 014 910 le même jour (78,8 %), 1 345 508 avant (21,2 %), jamais après. C'est vraisemblablement l'heure de création
  du paquet au poste. Il **remplace `pkt_cr_dtimes`**, qui est vide, pour le jour d'enrôlement et le délai de remontée.
- Préfixe à 5 chiffres = centre ? Invérifiable sans `master.registration_center` ; 3 543 valeurs, c'est beaucoup
  (étape 6).

**Échantillon de `registration_transaction`** (5.5, environ 32 000 transactions à 0,01 %) :
- **types** : SECUREZONE_NOTIFICATION, UPLOAD_PACKET, BIOGRAPHIC_VERIFICATION, QUALITY_CHECK, VALIDATE_PACKET,
  OSI_VALIDATE, PACKET_CLASSIFICATION, DEMOGRAPHIC_VERIFICATION, NOTIFICATION, UIN_GENERATOR, FMS, PACKET_RECEIVER,
  PRINT_SERVICE, MANUAL_VERIFICATION, BIOMETRIC_AUTHENTICATION, PACKET_REPROCESS ;
- **statuts** : SUCCESS, IN_PROGRESS, PROCESSED, FAILED, REPROCESS, ERROR, REJECTED ; `sub_status_code` en codes
  `RPR-…` (par exemple RPR-UIN-FAILED-009, RPR-SYS-EXCEPTION-001) ;
- **génération du NIU** : 1 009 tentatives IN_PROGRESS avec RPR-UIN-FAILED-009, contre 597 PROCESSED. Beaucoup de
  tentatives échouent puis sont reprises, ce qui cadre avec les rafales d'`id` perdus de `rid_uin_link` ;
- **notifications** : 1 072 en échec (surtout RPR-SYS-EXCEPTION-001), contre 929 réussies.

**Transactions par inscription** (5.6, environ 820 inscriptions au hasard) :

| Statut | Transactions par inscription |
|---|---|
| PROCESSED | 37,8 |
| REJECTED | 28,4 |
| FAILED | 34,4 |
| PACKET_UPLOADER_FAILED | 38,0 |
| PROCESSING | **132,8** (reprises en boucle) |

## Catalogue des indicateurs : proposition v1 (24/10/2026, à valider)

Tiré uniquement des étapes 1 à 5.

**Axes** :
- jour de réception (`registration.cr_dtimes`) ;
- jour d'enrôlement au poste (14 derniers chiffres du RID) ;
- jour du NIU (`rid_uin_link.entry_date`) ;
- type de demande (NEW, UPDATE, LOST, RES_UPDATE) ;
- centre (5 premiers chiffres du RID, **à confirmer**) ;
- poste d'enrôlement (10 premiers chiffres, à confirmer).

| N° | Indicateur | Règle | Source |
|---|---|---|---|
| I1 | Inscriptions reçues | inscriptions par jour de réception | registration |
| I2 | NIU générés | inscriptions NEW ayant un lien, au jour du NIU (flux) ou de réception (cohorte) | rid_uin_link |
| I3 | Mises à jour et pertes traitées | UPDATE et LOST ayant un lien (elles reprennent un NIU existant) | rid_uin_link |
| I4 | Devenir des inscriptions (partition exacte) | **NIU générés** = a un lien ; sinon **en cours** = PROCESSING ou ERROR ; **échouées** = FAILED ou PACKET_UPLOADER_FAILED ; **rejetées** = REJECTED | registration + rid_uin_link |
| I5 | Rejets par origine | **refusées au poste** (rejet à VALIDATE_PACKET d'une synchronisation REJECTED) ; **rejetées au traitement**, par étape : doublon démographique (DEMOGRAPHIC_VERIFICATION), vérification manuelle, génération du NIU, autres | registration + registration_list |
| I6 | Échecs par étape | FAILED par `latest_trn_type_code` (OSI_VALIDATE ≈ 94 %, UPLOAD_PACKET…) | registration |
| I7 | En cours par étape, dont bloqués depuis plus de 30 jours | en cours par `latest_trn_type_code` ; bloqué = dernière transaction de plus de 30 jours. **Stock à l'instant**, pas un fait par jour | registration |
| I8 | Délai réception → NIU | médiane et 90e centile de `entry_date − cr_dtimes`, NEW, par période et zone | registration + rid_uin_link |
| I9 | Délai enrôlement → réception | médiane et 90e centile de `cr_dtimes − horodatage du RID`, par centre : repère les postes qui remontent tard | registration |
| I10 | Synchronisés non reçus | synchronisés absents de `registration`, en transit (moins de 7 jours) ou perdus (au-delà) | registration_list + registration |

Phase 2, avec `registration_transaction` en capture des seules nouvelles lignes (table en ajout seul) :
- reprises par inscription ;
- tentatives de génération du NIU en échec ;
- notifications en échec ;
- durée de chaque étape.

**Sans source dans ces quatre tables** : âge et sexe des NIU (bloc « NIU générés par âge et par sexe »).

**Points à trancher** :
- A. Le Devenir selon I4 : une inscription qui a un NIU compte en « NIU générés » quel que soit son statut ; ERROR
  compte en « en cours ».
- B. Taux de rejet : avec ou sans les refus au poste ? Les refus au poste représentent 57 % des rejets.
- C. Préfixe du RID = centre : structures de `master.registration_center` et `master.location` nécessaires.
- D. `rid_uin_link` : quel processus la met à jour après insertion, et quelles colonnes ?
- E. Capture de `registration` (≈ 610 000 mises à jour par jour) : état courant et changements de statut seulement,
  pas de lake complet.

## Décisions du responsable sur le catalogue v1 (25/10/2026, 0 h 15)

- **A.** Toute inscription qui a un NIU compte en « NIU générés », quel que soit son statut. La règle I4 est retenue.
- **B.** Le taux de rejet **inclut les refus au poste**, en indiquant **l'étape** concernée par chaque refus ou rejet
  (`latest_trn_type_code`, par exemple VALIDATE_PACKET pour un refus au poste).
- **C.** Les **5 premiers chiffres du RID sont le code du centre d'inscription**. Confirmé.
- **D.** On ne saura pas quel processus met à jour `rid_uin_link`, ni quelles colonnes il touche. Parade : une fois la
  capture en place, les événements de mise à jour montreront quelles colonnes changent, et un contrôle signalera tout
  `entry_date` modifié.
- **E.** Besoin exprimé : **suivre chaque RID de sa création jusqu'à la génération du NIU, puis l'impression de la
  carte et sa remise**. Conséquences :
  - une table de suivi par inscription, avec les jalons datés : enrôlement (horodatage du RID), synchronisation,
    réception, étape et statut courants, NIU, impression, remise ;
  - l'impression et la remise viennent d'autres tables (`printing_orders`, `printing_orders_details`,
    `printing_processing_jobs`, `printing_shipped_cards`, déjà dans `dbz_publication`) : leurs structures sont à
    demander ;
  - le passage par chaque étape intermédiaire n'est daté que par `registration_transaction`. On peut la capter pour
    l'avenir, en ajout seul et sans snapshot, mais pas pour l'historique (206 Go) ;
  - **question ouverte** : le suivi doit-il être consultable RID par RID dans le tableau de bord (recherche d'un
    dossier), ou seulement en agrégats (délais entre jalons, dossiers bloqués à chaque jalon) ? Un RID affiché
    rattache le dossier à une personne : réservé à certains rôles, à faire valider par la sécurité.

## Décision sur le suivi par RID (25/10/2026, 0 h 20)

**Les deux** :
- des **agrégats** (délais entre jalons, dossiers bloqués à chaque jalon, par centre et par période) ;
- une **recherche par RID**. On saisit un RID, le résultat montre l'historique de son parcours jusqu'à son état
  courant.

**Aucun RID n'est jamais affiché** : pas de liste, pas de tableau de dossiers, pas de RID dans les agrégats.

Conception proposée, à valider avec la sécurité :
- **Recherche exacte seulement** : 29 chiffres saisis, ni recherche partielle, ni joker, ni liste de résultats. Le RID
  part dans le corps d'une requête POST et non dans l'adresse, pour ne pas finir dans les journaux.
- **Pas de RID dans `bi`.** La table de suivi est indexée par une empreinte HMAC du RID. L'API calcule l'empreinte du
  RID saisi avec la même clé secrète que le pipeline, puis cherche la ligne. Seul quelqu'un qui connaît déjà un RID
  peut retrouver son parcours.
- **Contenu de la réponse** :
  - les jalons datés : enrôlement, synchronisation, réception, NIU, impression, remise ;
  - le centre (préfecture, région) ;
  - les étapes franchies et l'étape et le statut courants ;
  - jamais le NIU ni aucune donnée d'identité.
- **Accès** :
  - un rôle Keycloak dédié ;
  - un utilisateur régional ne voit que les dossiers de sa région (centre lu dans le RID) ;
  - chaque recherche est journalisée (qui, quand, empreinte du RID, trouvé ou non) ;
  - un plafond de recherches par utilisateur.
- **Profondeur de l'historique** :
  - pour tout dossier : les jalons ci-dessus, plus l'étape et le statut courants ;
  - le détail de chaque étape franchie n'existe qu'à partir de la mise en service de la capture de
    `registration_transaction` (en ajout seul, sans snapshot) et des changements de statut de `registration`. Pour un
    dossier plus ancien, l'historique détaillé commence à cette date. Un rattrapage ponctuel de l'historique
    (`registration_transaction`, colonnes utiles seulement, par lots) reste possible plus tard, à décider.

## Étape 6, première partie (25/10/2026, 0 h 30) : horodatage du RID

- Les 6 360 418 RID ont tous un horodatage valide (AAAAMMJJHHMISS dans les 14 derniers chiffres). Aucun n'est écarté.
- **Délai enrôlement → réception** (`cr_dtimes − horodatage du RID`) :

| Délai | Inscriptions | Part |
|---|---|---|
| reçue avant l'horodatage | 1 | — |
| moins d'une heure | 485 193 | 7,6 % |
| 1 h à 1 jour | 5 353 881 | **84,2 %** |
| 1 à 3 jours | 475 890 | 7,5 % |
| 3 à 7 jours | 40 005 | 0,6 % |
| 7 à 30 jours | 5 303 | 0,08 % |
| plus de 30 jours | 145 | — |

  La plupart des paquets arrivent dans la journée de l'enrôlement, sans doute à l'envoi groupé en fin de journée ;
  8 % arrivent plus tard.
- **La synchronisation suit toujours l'horodatage** (une seule exception sur 6 362 660). Une seule inscription est
  reçue « avant » son horodatage. **L'horodatage du RID est donc l'heure d'enrôlement au poste**, premier jalon du
  suivi par RID. On a maintenant, pour chaque inscription : enrôlement → synchronisation → réception → NIU.
- En attente : 6.3 (forme des préfixes) et structures des tables `printing_*`.
- **6.4 abandonnée** : le référentiel est déjà capté (connecteurs `mosip-master-cdc` et `lake-master`, puis dbt
  `dim_zone`, puis `bi.zone`). Comme la chaîne des pré-inscriptions, il est en test avec une mise à jour toutes les
  5 minutes (précision du responsable, 25/10/2026). Le rattachement préfixe → centre se vérifie donc sur la BD
  traitement (`dwh.dim_zone`, `bi.zone`). Ensuite, le test dbt `code_centre` → `dim_zone` du modèle
  `stg_regprc__registration` le mesurera en continu.

## Référentiel sur la BD traitement (25/10/2026, 0 h 40)

Le suivi de l'impression et de la remise viendra **après l'enrôlement** (décision du responsable). Les tables
`printing_*` sont donc reportées.

Le référentiel est dans le lake (`lake.mosip_master_registration_center`, une ligne par changement et par langue : 2
lignes par centre), puis dans `bi.zone` :

| Niveau | Zones | Codes |
|---|---|---|
| région | 7 (dont HORS_REFERENTIEL) | R1… R6 |
| préfecture | 48 | P1… |
| commune | 136 | COM… |
| canton | 528 | CNT… |
| localité | 7 971 | L… |
| centre | **8 841** (dont CENTRE_NON_REFERENCE) | **5 chiffres** (10001…) |

Les codes de centre ont bien le format du préfixe des RID (5 chiffres). On compte 8 841 centres au référentiel pour
3 543 préfixes présents dans les RID : beaucoup de centres n'ont encore reçu aucune inscription. Les deux tables sont
sur deux serveurs : la correspondance exacte passe par un export des préfixes (étape 7).

Précision du responsable (25/10/2026, 0 h 45) : les centres sans inscription sont **normaux**. Ce sont de nouveaux
centres configurés pour les prochaines vagues d'enrôlement, et l'écart 8 841 / 3 543 n'est pas une anomalie.
L'étape 7 est abandonnée. Un préfixe de RID absent du référentiel sera signalé en continu par le test dbt
`code_centre` → `dim_zone` une fois l'enrôlement capté, et compté sous « Centre non référencé ».

## Catalogue des indicateurs de l'enrôlement : v2 (25/10/2026, à valider)

Le v1, plus les décisions A à E et la décision sur le suivi par RID. Impression et remise : plus tard. Âge et sexe :
pas de source dans les tables retenues.

**Axes** :
- jour d'enrôlement (horodatage du RID) ;
- jour de réception (`cr_dtimes`) ;
- jour du NIU (`entry_date`) ;
- type de demande ;
- centre (5 premiers chiffres du RID), puis le territoire de `bi.zone` jusqu'à la région ;
- poste (10 premiers chiffres), en option.

| N° | Indicateur | Règle | Nature |
|---|---|---|---|
| I1 | Inscriptions reçues | par jour de réception | fait par jour |
| I2 | NIU générés | inscriptions NEW ayant un lien `rid_uin_link`, quel que soit leur statut (A) ; par jour du NIU (flux) ou de réception (cohorte) | fait par jour |
| I3 | Mises à jour et pertes traitées | UPDATE et LOST ayant un lien | fait par jour |
| I4 | Devenir des inscriptions | NIU générés (a un lien) ; sinon en cours (PROCESSING, ERROR), échouées (FAILED, PACKET_UPLOADER_FAILED), rejetées (REJECTED). La somme fait les inscriptions | fait par jour (cohorte) |
| I5 | Rejets et taux de rejet | **tous les rejets, refus au poste compris** (B) ; taux = rejetées / inscriptions ; ventilés par **étape** (VALIDATE_PACKET = refus au poste, DEMOGRAPHIC_VERIFICATION, MANUAL_VERIFICATION, UIN_GENERATOR…) | fait par jour |
| I6 | Échecs par étape | FAILED et PACKET_UPLOADER_FAILED par étape (OSI_VALIDATE, UPLOAD_PACKET…) | fait par jour |
| I7 | En cours par étape, dont bloqués depuis plus de 30 jours | dernière transaction de plus de 30 jours | stock à l'instant |
| I8 | Délai réception → NIU | médiane et 90e centile, NEW | par période et zone |
| I9 | Délai enrôlement → réception | médiane, part au-delà de 3 jours, par centre et poste | par période et zone |
| I10 | Synchronisés non reçus | en transit (moins de 7 jours) ou perdus | stock à l'instant |
| I11 | Suivi d'un dossier | recherche exacte par RID (jamais affiché), résultat : jalons datés (enrôlement, synchronisation, réception, NIU), centre et territoire, étape et statut courants, étapes franchies (détail à partir de la capture de `registration_transaction`) | recherche |

## Étape 7 (26/10/2026, 13 h) : `registration.status_comment`, motif des rejets, échecs et en cours

Demande du responsable : expliquer chaque cas à la direction par le motif que MOSIP écrit dans `status_comment`
(texte libre, jusqu'ici non capté). Relevé R13, en lecture seule, chiffres masqués (`#`) :

| Devenir | Inscriptions | Messages distincts | Suite de 6 chiffres ou plus | Adresse électronique |
|---|---|---|---|---|
| rejeté | 158 487 | 20 | 0 | 0 |
| échoué | 108 978 | 44 | 0 | 0 |
| en cours | 64 720 | 230 | 56 | 0 |

- Les 56 suites de chiffres (6 à 12 chiffres) sont des morceaux d'identifiants de requête de l'ABIS (UUID, « Identify
  / Insert Response Failed for Request ID … »), ni RID (29 chiffres) ni NIU : **aucune donnée de personne**.
- Messages principaux :

| Devenir | Étape (`reg_stage_name`) | Commentaire | Inscriptions |
|---|---|---|---|
| rejeté | PacketValidatorStage | Rejected by Supervisor | 90 810 |
| rejeté | DemoDedupeStage | Biometric Duplicate was Found in ABIS | 37 690 |
| rejeté | ManualVerificationStage (et 5 autres étapes) | Match Found by Manual Verifier | 28 355 |
| rejeté | UinGeneratorStage | UIN Generation failed - Invalid Input Parameter - … | 1 140 |
| rejeté | OSIValidatorStage | UIN or RID of Parent Not Found in Packet | 315 |
| échoué | OSIValidatorStage | Biometric data (- Iris / - Finger / - FACE) did not match | 97 576 |
| échoué | PacketUploaderStage | Packet not found in LANDING_ZONE, Packet Upload Failed, Hash Code Validation Failed | 6 988 |
| échoué | OSIValidatorStage | Biometric data … / UIN not available in database | 3 319 |
| en cours | BioDedupeStage | Manual verification Sent to queue | 51 707 |
| en cours | ManualVerificationStage | Error in manual verification | 6 775 |
| en cours | PacketReceiverStage | Packet is Uploaded to Landing Zone | 4 915 |

Constats :
- « Refus au poste » est confirmé : rejet par le superviseur du centre (90 810).
- Le libellé « Déduplication démographique » trompait : ces 37 690 rejets sont des **doublons biométriques** trouvés
  par l'ABIS à l'étape DemoDedupeStage.
- 9 échecs sur 10 : la vérification biométrique de la personne qui valide le paquet (agent, superviseur ou parent,
  étape OSI) ne concorde pas ; qui des trois : à confirmer avec l'équipe MOSIP.
- `reg_stage_name` et `latest_trn_type_code` ne concordent pas toujours : la file de vérification manuelle est à
  BioDedupeStage pour `reg_stage_name`, à MANUAL_VERIFICATION pour la dernière transaction.

**Décisions du responsable (26/10/2026)** : `status_comment` est capté ; le bloc « Où s'arrêtent les paquets »
montre pour chaque devenir l'étape (`reg_stage_name`), le motif traduit en français avec le commentaire de MOSIP, et
le nombre de cas ; traductions validées. Le texte reste dans l'ODS, seul le code du motif est publié vers `bi`.
