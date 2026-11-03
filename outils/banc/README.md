# Banc de test de la chaîne enrôlement

Ce banc vérifie les modèles dbt de l'enrôlement et la publication vers `bi` sur un PostgreSQL local jetable, sans
Kafka ni MOSIP. Il utilise les vraies migrations du backend (V1 à V15), les vrais scripts SQL de droits et le vrai
`scripts/publier-indicateurs.sh`.

`minidbt.py` est un remplaçant minimal de dbt (Jinja, `ref`, `source`, `is_incremental`, `this`, seeds, index, grants,
post-hooks, tests génériques et singuliers). Il a servi parce que dbt n'était pas installable dans l'environnement de
Claude. Là où dbt est installé, `dbt build` reste la référence : le banc ne remplace pas un passage du vrai dbt.

## Prérequis

- PostgreSQL 15 ou plus, local, en authentification `trust` (le banc crée des rôles sans mot de passe) ;
- `psql` ;
- Python 3 avec `jinja2` et `pyyaml` ;
- le dépôt `mosip-bi-reporting` à côté de `mosip-cdc` (sinon, variable `REPORTING`).

## Scénario (environ une minute)

```
export PGHOST=/tmp PGUSER=postgres          # PostgreSQL de test
outils/banc/installer.sh                    # base mosip_bi vierge, migrations V1 à V15 ; la chaîne tourne avec une ODS vide
psql -U ods_writer -d mosip_bi -f outils/banc/01_snapshot.sql      # snapshot initial : 8 inscriptions, 11 synchronisations
outils/banc/passage.sh
psql -U ods_writer -d mosip_bi -f outils/banc/02_flux.sql          # NIU, réception, nouvelle synchronisation…
outils/banc/passage.sh
psql -U api_reader -d mosip_bi -f outils/banc/etat_bi.sql          # faits publiés et contrôles
psql -U api_reader -d mosip_bi -v zone= -f outils/banc/api.sql     # requêtes actuelles de l'API (EnrolementRepository)
outils/banc/passage.sh --full-refresh                              # doit redonner exactement les mêmes tables
```

`01_snapshot.sql` et `02_flux.sql` jouent le rôle des connecteurs : `insert` (ou upsert) dans l'ODS avec un offset
Kafka croissant, et ajout dans le journal du lake de `rid_uin_link`. La clé du suivi vaut `cle-du-banc`
(`SUIVI_HMAC_CLE= outils/banc/passage.sh` publie sans le suivi).

## Résultats attendus après 02_flux.sql (vérifiés le 25/10/2026)

- **Suivi** : 11 RID dans `dwh.suivi_inscription`, dont 2 synchronisés non reçus ; le deuxième passage n'en recalcule
  que 5.
- **Devenir** : 9 paquets reçus = 3 NIU + 2 en cours + 1 échoué + 2 rejetés + 1 non classé (statut RESUMABLE inconnu).
- **Étapes** : rejetés = Refus au poste 1 + Déduplication démographique 1 ; échoués = Validation opérateur et
  superviseur 1 ; en cours = Réception du paquet 1 + Génération du NIU 1 (le dossier bloqué en vérification manuelle
  depuis le 05/07 a reçu son NIU dans le flux).
- **Motifs** (28/10/2026) : rejetés = Rejeté par le superviseur du centre 1 + Doublon biométrique trouvé par l'ABIS 1 ;
  échoués = Iris non concordant 1 ; en cours = Paquet reçu, en attente de traitement 1 + Motif non répertorié 1 (R7,
  message absent du catalogue) ; chaque motif publié avec sa ligne « À vérifier » (`motif_piste`).
- **Reprocessing et types de demande** (31/10/2026) : 1 dossier en reprocessing, la récupération de NIU (LOST) du
  24/10, en cours avec une dernière transaction REPROCESS ; le dossier RESUMABLE (non classé), lui aussi en REPROCESS,
  n'y compte pas. `api.sql` : 1 demande de mise à jour (UPDATE rejetée du 02/10), 1 demande de NIU perdu. Onglet
  « En reprocessing » (02/11/2026) : `bi.stock_en_cours_motif` en compte 1, sur la ligne Génération du NIU, motif
  « Motif non répertorié » (AUTRE), comme `bi.fait_enrolement_jour` (test `assert_enrolement_motifs_egal_devenir`).
  Depuis le 02/11/2026, 6 alertes et non 7 : l'alerte `entry_date` modifiée ne regarde que les jours récents.
- **Impression des cartes** (lot 8b, 03/11/2026) : 7 commandes dans `dwh.suivi_carte` ; le deuxième passage en
  recalcule 5 (C1 par le lien RID → NIU modifié, C2 par sa remise, C3 par son annulation, C6 et C7 par leur
  commande). `bi.fait_demande_impression_jour` : 7 demandes = 4 envoyées + 2 en attente (C3, C7) + 1 rejetée (C4),
  dont 2 annulées (C5 CANCEL_PHOTO, C3 NON_REPERTORIE). `bi.fait_carte_jour` : 4 cartes expédiées = 2 remises
  (hors ligne, en ligne) + 2 à remettre (la carte orpheline K9 n'est comptée nulle part). `bi.fait_delai_carte_jour` :
  18 jours (C1) et 20 jours (C2), médiane 18. `etat_bi.sql` montre les contrôles ; `--full-refresh` redonne les mêmes
  tables. 3 alertes de plus que l'enrôlement : centre 99999 non référencé, motif d'annulation non répertorié, et
  `assert_impression_anomalies_cartes` (2 lignes pour C3 : carte expédiée d'une commande en attente, date de remise
  sans remise) ; au premier passage, `assert_impression_cartes_sans_commande` (K9) à la place du motif.
- **Contrôles** : 0 échec ; 7 alertes attendues : 2 centres non référencés (99999, 88888), 1 devenir non classé,
  1 statut inconnu, 1 horodatage de RID illisible, 1 `entry_date` modifiée, 1 commentaire de MOSIP non répertorié,
  1 genre de l'ID Repository non reconnu (« Inconnu », R7).
- **Profil des NIU** (lot 6, 29/10/2026) : 3 NIU dans `bi.fait_niu_profil_jour` comme dans `bi.fait_niu_jour` :
  01/10 Savanes (R1) F 36-45 ; 06/10 Hors référentiel (centre 99999) I inconnu (pas encore enrichi) ; 25/10 Savanes
  H 15-18. `bi.fait_niu_nationalite_jour` : Togo (code TOGO de la liste « nationality »), Non renseignée, BENIN
  (absent de la liste, gardé tel quel). R7 (enrichi, sans NIU) n'y figure pas. La requête du rattrapage
  (`spark/commun/sources.py`, source `inscriptions`), lancée par `spark_reader`, ne rend que le RID de R4.
- **Suivi d'un dossier** : 11 lignes dans `bi.suivi_dossier`, retrouvées par
  `hmac('<RID>', 'cle-du-banc', 'sha256')`, jamais avec une autre clé ; 6 avec un motif (29/10/2026 : rejetés
  REFUS_SUPERVISEUR et DOUBLON_ABIS, échoué IRIS_NON_CONCORDANT, en cours RECU_EN_ATTENTE et AUTRE, non classé AUTRE),
  aucun pour les 3 NIU et les 2 non reçus ; 29 lignes dans `bi.ref_motif`. `scripts/rattraper-motif-suivi.sh`, avec un
  `compose/.env` de banc (`TRAITEMENT_PG_HOST=/tmp`, `PUBLISHER_PASSWORD=banc`, `SUIVI_HMAC_CLE=cle-du-banc`), remet
  les 6 motifs effacés puis, relancé, n'en touche aucun.
- **Reconstruction** : `--full-refresh` et un passage sans nouvel événement donnent des tables identiques à celles du
  passage incrémental.
