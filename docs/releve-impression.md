# Relevé de l'impression et de la remise des cartes (`mosip_regprc`, tables `printing_*`)

Relevé du 02/11/2026, fait avec le responsable, requête par requête, en lecture seule : comptages seulement, aucune
valeur personnelle affichée (ni RID, ni NIU, ni numéro de carte, ni agent). Sert le lot 8 (page Impression des cartes,
frise de la Vue d'ensemble). Les structures ont été fournies par le responsable (`\d`).

## Étape 1 : structures et volumes (statistiques de PostgreSQL)

| Table | Lignes | Taille | Insertions / mises à jour / suppressions | Rôle |
|---|---|---|---|---|
| `printing_orders` | 6,18 M (compté) | 6,1 Go | 1,0 M / 6,6 M / 0 | une commande d'impression par dossier (RID unique) ; très modifiée |
| `printing_orders_details` | 22,2 M | 6,8 Go | 3,9 M / 0 / 0 | historique des statuts de chaque commande ; ajout seul |
| `printing_processing_jobs` | 256 000 | 75 Mo | 33 000 / 32 000 / 0 | lots envoyés à l'imprimeur |
| `printing_shipped_cards` | 6,09 M (compté) | 2,5 Go | 0,9 M / 1,0 M / 0 | cartes expédiées et leur remise ; modifiée à la remise |

Les quatre tables sont dans `dbz_publication`. `printing_orders_status` est une vue (nombre de commandes par
`prc_status`) : **à ne pas utiliser** (décision du responsable). `printing_orders.cr_dtimes` est une colonne calculée par
MOSIP depuis le RID : la réplication logique ne la transmet pas.

**Colonnes jamais lues** : `printing_orders.uin` (NIU), `citizen_fingers_count` (biométrie), `center_name` (texte ;
redondant) ; `printing_orders_details.details` (texte libre), `cr_by` ; `printing_shipped_cards.serial_number`,
`logical_number`, `tracking_number`, `box_number` (carte et colis), `delivered_by` (agent),
`has_finger_biometrics_exception` (biométrie).

## Étape 2 : ce que disent les données

**Commandes** (`printing_orders`) : 6 179 588, toutes `NEW_PRINTING` / `PA` (colonnes sans information), depuis le
28/11/2023, par vagues (670 000 en juin 2025, 632 000 en avril 2026, 641 000 en septembre 2026, 11 000 en mai 2026).

| `prc_status` | Commandes | Sans `issuing_date` | Lecture |
|---|---|---|---|
| OK | 6 177 472 | 35 | envoyée à l'imprimeur (`issuing_date`) |
| NEW | 2 366 | 2 358 | pas encore envoyée ; 2 214 anciennes (depuis novembre 2023) : bloquées ; 152 du jour |
| KO | 8 | 8 | rejetée |

`retry_count` vaut 1 jusqu'en février 2026, puis 2 ou plus, pour presque toutes les commandes : sens incertain, non
utilisé.

**Commandes et cartes** :

| Commande | Carte expédiée | Remise | Commandes |
|---|---|---|---|
| OK | oui | DELIVERED | 4 643 047 |
| OK | oui | NOT_DELIVERED | 1 444 429 |
| OK | non | — | 91 806 (dont 680 annulées) |
| NEW | non | — | 1 450 |
| NEW | oui | DELIVERED | 468 |
| NEW | oui | NOT_DELIVERED | 448 |
| KO | non | — | 8 |

Aucune carte sans commande.

**Cartes** (`printing_shipped_cards`) : 6 088 392, toutes `status = IN_TRANSIT` (colonne sans information), depuis le
04/10/2024. La **remise est dans MOSIP** :

| `delivery_status` | `delivery_mode` | Cartes | Avec date de remise |
|---|---|---|---|
| DELIVERED | OFFLINE | 4 446 113 | toutes |
| DELIVERED | ONLINE (jusqu'au 14/10/2026) | 197 370 | toutes |
| DELIVERED | SUPPORT (octobre 2024 à avril 2025) | 32 | toutes |
| NOT_DELIVERED | — | 1 444 068 | aucune |
| NOT_DELIVERED | SUPPORT | 809 | toutes (anomalie) |

**Lieu de remise** : `delivery_site` = `0000` suivi du code de centre à 5 chiffres du RID, pour 6 088 386 cartes sur
6 088 392 (6 remises ailleurs). Le territoire se lit donc par le RID ; `delivery_site` n'est pas capté.
`center_name` : 3 740 noms pour 3 871 centres du RID (3 893 couples), redondant avec le référentiel des centres.

**Historique** (`printing_orders_details`, `source_app = PRINTING`, `status_ind = FUNC`) :

| `status_code` | Événements | Commandes | Lecture |
|---|---|---|---|
| NEW-PRINT-REQUEST-RECEIVED | 6 181 196 | 6 181 196 | commande reçue |
| NEW-PRINT-REQUEST-SENT | 6 225 637 | 6 175 951 | envoyée à l'imprimeur |
| NEW-PRINT-BOXED (`IN_TRANSIT`) | 6 357 274 | 6 086 582 | mise en boîte, expédiée ; certaines plusieurs fois |
| CARD-DELIVERED | 4 812 488 | 4 649 440 | remise ; certaines enregistrées deux fois |
| PRINT-REQUEST-ERR (`CORE-PRINTING-IDPS-1`) | 302 825 | 172 354 | erreur d'envoi à l'IDPS, puis nouvel essai ; pic en septembre 2025, presque nul depuis janvier 2026 |
| NEW-PRINT-CANCELED (`TERMINATED`) | 693 | 693 | annulée : CANCEL_PHOTO 643, CANCEL_SEX 36, CANCEL_NAME 10, PERSONALIZATION_MANAGER_REPORTED_ERROR 4 |

Avant octobre 2024, seules des réceptions de commande. Environ 2 M d'événements par mois (≈ 70 000 par jour). Les
annulées restent `OK` sans carte (680) ou expédiées non remises (13). Compter des commandes (première date de chaque
événement), jamais des événements.

**Lots** (`printing_processing_jobs`) : environ 10 000 par mois ; écarts commandes / envois dus aux nouveaux essais.
Non captée : l'historique donne mieux la même information.

**NIU sans commande** (`rid_uin_link` sans `printing_orders`) :

| Type | NIU | Sans commande |
|---|---|---|
| NEW | 6 176 842 | 55 |
| UPDATE | 19 484 | 16 192 |
| LOST | 1 641 | 1 301 |

Une mise à jour ou une perte ne déclenche en général pas de carte ; l'indicateur suivi est « NIU de première
inscription sans commande ».

**Délais médians** : commande → envoi 8 h 30 ; envoi → expédition 4 jours ; expédition → remise 22 jours (cartes
remises).

## Décisions du responsable (02/11/2026)

1. Correspondance des indicateurs (`docs/indicateurs.md` de `mosip-bi-reporting`, section Impression des cartes) :
   en attente = `NEW` ; rejetées = `KO` ; **annulées à part**, avec leur motif.
2. Remises : pourcentage des cartes **expédiées** (comme la maquette).
3. Colonnes captées : celles de la conception (lot 8), tant qu'elles couvrent tous les indicateurs.
4. Capture par un connecteur dédié avec snapshot initial : **accord du DBA** obtenu.

## Anomalies (à afficher et signaler, jamais corrigées)

- 916 cartes expédiées dont la commande est encore `NEW` (468 remises) ;
- 809 cartes `NOT_DELIVERED` en mode `SUPPORT` avec une date de remise ;
- 2 214 commandes `NEW` anciennes (depuis novembre 2023) ;
- environ 270 000 commandes mises en boîte plusieurs fois, 160 000 remises enregistrées deux fois ;
- 6 cartes remises dans un autre centre que celui de l'enrôlement.
