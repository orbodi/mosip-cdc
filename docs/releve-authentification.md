# Relevé des authentifications (`mosip_ida`, tables `auth_transaction` et `otp_transaction`)

Relevé des 03 et 04/11/2026, fait avec le responsable, requête par requête, en lecture seule : structures, comptages
et messages fixes seulement, aucune valeur personnelle affichée (ni `ref_id`, ni jeton, ni code). Sert le lot 9 (page
Authentifications). **Seules ces deux tables sont lues** (décision du responsable, 03/11/2026).

## Étape 1 : tables et volumes

| Table | Lignes (estimées) | Taille | Lecture |
|---|---|---|---|
| `ida.auth_transaction` | ≈ 3,25 M | 12 Go | une ligne par authentification ; index sur `id` et `cr_dtimes` seulement |
| `ida.otp_transaction` | ≈ 83 900 | 31 Mo | un code OTP demandé ; index sur `id` |
| `ida.identity_cache` | 5,9 M | 2,6 To | identités et biométrie : **jamais lue**, même pour un comptage |

Autres tables de `mosip_ida` (`credential_event_store`, `batch_*`, clés) : mécanismes internes d'IDA, sans indicateur.

**Colonnes jamais lues** : `auth_transaction.ref_id` (référence de l'individu), `token_id` et `static_tkn_id` (jetons
de la personne), `request_signature`, `response_signature`, `request_trn_id` ; `otp_transaction.ref_id`, `otp_hash`.

## Étape 2 : ce que disent les données

**Volume par mois** (index de `cr_dtimes`) : 3 250 928 transactions de novembre 2023 au 03/11/2026. Quelques essais
avant décembre 2024, puis des vagues : décembre 2024 à février 2025 (≈ 761 000), avril 2026 (≈ 439 000), septembre
2026 (≈ 518 000) ; ≈ 5 000 par jour début novembre 2026. Les 510 499 de l'ancien BI ne correspondent à aucun cumul
(1,4 M à la mi-janvier 2026) : non reproduits.

**30 derniers jours** (au 03/11/2026, 177 510 transactions) :

| Appelant (`requested_entity_id`) | Type | Transactions | Réussies |
|---|---|---|---|
| `mosip-regproc-client` | INTERNAL : vérifications du traitement des paquets | 172 612 (97,2 %) | 24 977 (14,5 %) |
| `AU-ANID` (« Atos ») | PARTNER : le seul partenaire | 3 804 | 2 951 (77,6 %) |
| `mosip-resident-client` | INTERNAL : portail du résident | 1 067 | 927 |
| `ussd-client` | INTERNAL : service USSD | 47 | 40 |

- `status_code` : `Y` (réussie) ou `N` (échouée). `cr_by` vaut toujours `IDA`.
- `auth_type_code` est une **liste de modalités** (`FINGERPRINT-AUTH,IRIS-AUTH,FACE-AUTH`), parfois avec un doublon
  (`KYC-AUTH,OTP-AUTH,KYC-AUTH`). Vus : empreinte, iris, visage (seuls ou combinés), `OTP-AUTH`, `KYC-AUTH`,
  `OTP-REQUEST` ; aucun `DEMO-AUTH` sur 30 jours.
- `OTP-REQUEST` (2 732) : demande d'envoi d'un code, **pas une authentification**.
- Le traitement des paquets ne fait que de la biométrie ; les usagers passent presque tous par un code OTP (eKYC
  d'Atos, portail, USSD).

**Messages d'échec** (`status_comment`, chiffres masqués, messages vus au moins 20 fois) : phrases fixes d'IDA, au plus
110 caractères, **aucun long nombre** ; 3 messages rares côté usagers.

| Bloc | Motif proposé | Messages | Échecs (30 j) |
|---|---|---|---|
| Traitement des paquets | Biométrie non concordante | « Finger / Iris / Face Authentication … Failed » | 106 076 |
| | Biométrie absente du dossier d'authentification | `IDA-BIA-006` « Biometric data … not available in database » | 21 151 |
| | NIU absent de la base d'authentification | `IDA-MLC-018` « UIN not available in database » | 17 637 |
| | Modalité verrouillée par le résident | `IDA-MLC-019` « … Auth Type is Locked for the UIN » | 34 |
| Usagers | Code OTP ou eKYC refusé | « OTP Authentication Failed », « KYC … OTP … Failed » | 419 |
| | Aucun mode d'authentification demandé | `IDA-MLC-008` | 227 |
| | Type d'identifiant non configuré | `IDA-MLC-015` « Identity Type - USERID not configured » (demandes d'OTP) | 353 |

À signaler à l'ANID : 17 637 vérifications du traitement des paquets sur un NIU qu'IDA ne connaît pas encore
(diffusion du NIU vers IDA ?) ; 353 demandes d'OTP d'Atos avec un type d'identifiant non configuré (`USERID`).

**`otp_transaction`** (toute l'histoire) : 50 781 `used` (60,5 %), 33 092 `active` (jamais utilisés, presque tous
expirés). `generated_dtimes` toujours vide, `validation_retry_count` toujours à 0 : date retenue `cr_dtimes`, pas
d'indicateur d'essais.

## Décisions du responsable

1. **03/11/2026** : seules `ida.auth_transaction` et `ida.otp_transaction` sont lues (pas de `mosip_pms`) ; le
   partenaire se lit dans `auth_transaction`.
2. **03/11/2026, option A** : deux blocs jamais additionnés. Authentifications des **usagers** (partenaires, portail
   du résident, USSD) en tête de page ; **vérifications biométriques du traitement des paquets**
   (`mosip-regproc-client`) dans un bloc à part.
3. **04/11/2026, maquette validée** : bloc « Partenaires et canaux » (nom, type, requêtes, part, réussies, taux
   d'échec, codes OTP demandés, dernière requête ; sans code MOSIP affiché) ; requêtes par semaine en deux barres
   côte à côte avec leur chiffre.
