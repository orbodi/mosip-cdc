# Banc de test de la chaîne enrôlement

Ce banc vérifie les modèles dbt de l'enrôlement et la publication vers `bi` sur un PostgreSQL local jetable, sans
Kafka ni MOSIP. Il utilise les vraies migrations du backend (V1 à V9), les vrais scripts SQL de droits et le vrai
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
outils/banc/installer.sh                    # base mosip_bi vierge, migrations V1 à V9 ; la chaîne tourne avec une ODS vide
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
- **Contrôles** : 0 échec ; 6 alertes attendues : 2 centres non référencés (99999, 88888), 1 devenir non classé,
  1 statut inconnu, 1 horodatage de RID illisible, 1 `entry_date` modifiée, 1 commentaire de MOSIP non répertorié.
- **Suivi d'un dossier** : 11 lignes dans `bi.suivi_dossier`, retrouvées par
  `hmac('<RID>', 'cle-du-banc', 'sha256')`, jamais avec une autre clé ; 6 avec un motif (29/10/2026 : rejetés
  REFUS_SUPERVISEUR et DOUBLON_ABIS, échoué IRIS_NON_CONCORDANT, en cours RECU_EN_ATTENTE et AUTRE, non classé AUTRE),
  aucun pour les 3 NIU et les 2 non reçus ; 29 lignes dans `bi.ref_motif`. `scripts/rattraper-motif-suivi.sh`, avec un
  `compose/.env` de banc (`TRAITEMENT_PG_HOST=/tmp`, `PUBLISHER_PASSWORD=banc`, `SUIVI_HMAC_CLE=cle-du-banc`), remet
  les 6 motifs effacés puis, relancé, n'en touche aucun.
- **Reconstruction** : `--full-refresh` et un passage sans nouvel événement donnent des tables identiques à celles du
  passage incrémental.
