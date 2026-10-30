# mosip-cdc : pipeline de données du BI Reporting ANID

Ce pipeline alimente le tableau de bord (`orbodi/mosip-bi-reporting`) à partir des bases MOSIP 1.1.5 :
- il capte en continu les changements de MOSIP ;
- il les range dans la BD traitement `mosip_bi` ;
- dbt calcule les indicateurs toutes les 5 minutes ;
- un script les publie dans le schéma `bi`, que lit l'API.

```
MOSIP (EDB PostgreSQL)        Serveur pipeline (Docker)                     BD traitement mosip_bi
mosip_prereg ─┐                                                             lake  : journal des changements
mosip_master ─┼─ Debezium ─→ Kafka ─→ connecteurs JDBC ───────────────→    ods   : état courant (pré-inscriptions, enrôlement)
mosip_regprc ─┘      │                                                      dwh, dm_* : modèles dbt
                     └─→ Spark (enrichissement : API de pré-inscription,       bi    : contrat lu par l'API
                                ID Repository pour les NIU)
```

## Chaînes en place

| Domaine | Source MOSIP | Connecteurs | Modèles dbt | Publié dans `bi` |
|---|---|---|---|---|
| Référentiel | `master.location`, `registration_center`, `dynamic_field` | `mosip-master-cdc`, `lake-master` | `dwh/referentiel`, `dim_zone` | `bi.zone` |
| Pré-inscriptions | `prereg.applicant_demographic` + API de pré-inscription (Spark) | `mosip-prereg-cdc`, `lake-prereg`, `ods-prereg`, `lake-enrichissement`, `ods-enrichissement` (**non versionnés**) | `dwh/prereg`, `dm_preinscription` | `bi.fait_preinscription_*`, `source_fraicheur('preinscription')` |
| Enrôlement | `regprc.registration`, `rid_uin_link`, `registration_list` | `mosip-regprc-cdc`, `ods-regprc-registration`, `ods-regprc-rid-uin-link`, `ods-regprc-registration-list`, `lake-regprc-rid-uin-link` | `dwh/regprc` (`suivi_inscription`), `dm_enrolement` | `bi.fait_enrolement_jour`, `fait_niu_jour`, `fait_arret_etape_jour`, `stock_en_cours`, `fait_delai_jour`, `stock_synchro_non_recue`, `suivi_dossier` (empreinte du RID), `source_fraicheur('enrolement')` |
| Profil des NIU (lot 6) | ID Repository appelé avec le RID des NIU (Spark, `--source inscriptions`) | `lake-regprc-enrichissement`, `ods-regprc-enrichissement` | `stg_regprc__enrichissement`, `dim_centre_region`, `fait_niu_profil_jour` | `bi.fait_niu_profil_jour`, `fait_niu_nationalite_jour` |

Le détail de l'enrôlement (règles, mise en service, reprise) est dans `docs/enrolement.md`.

## Arborescence

- `compose/` : `docker-compose.yml` (Kafka, Kafka Connect/Debezium, interfaces, dbt, Spark) et
  `docker-compose.dashboard.yml` (API et front) ; `.env.example` à copier en `compose/.env` (`chmod 600`, jamais
  versionné).
- `kafka/` : `topics.sh` (Kafka refuse l'auto-création) et `connecteurs/` (configurations à envoyer à Kafka Connect ;
  mots de passe à reporter dans une copie hors du dépôt).
- `sql/mosip/` : prérequis à exécuter par le DBA sur les bases MOSIP (droits, publications).
- `sql/traitement/` : scripts numérotés pour la BD traitement, chacun indique le rôle qui l'exécute.
- `sql/publication/` : fragments SQL inclus par `scripts/publier-indicateurs.sh`.
- `dbt/` : projet dbt `mosip_bi` (`models/dwh`, `models/dm_*`, `seeds/` de correspondances, `tests/` de contrôle).
- `spark/` : jobs d'enrichissement (`enrichissement_flux.py` en continu, `rattrapage_stock.py` par cron), pour les
  pré-inscriptions (API de pré-inscription, par défaut) et les NIU (ID Repository, `--source inscriptions`) ;
  sources décrites dans `spark/commun/sources.py`.
- `scripts/` : `run-analytique.sh` (dbt build puis publication), `publier-indicateurs.sh`, `rafraichir-direct.sh`,
  `check-health.sh`, `charger-suivi.sh` (chargement complet du suivi d'un dossier, à la main).
- `ops/` : cron (`/etc/cron.d/mosip-bi`), logrotate et `reseau/` (routage des réponses reçues sur ens34, service
  systemd `routage-ens34`).
- `outils/banc/` : banc de test local de la chaîne enrôlement (PostgreSQL jetable, sans Kafka).

## Exploitation

- **Adresse du tableau de bord** : http://172.16.26.86:5173/enrolement (interface ens34, `FRONT_HOTE` de
  `compose/.env`). Pour qu'elle marche aussi depuis le réseau 172.16.44.0/24, les réponses aux connexions reçues sur
  ens34 repartent par ens34 (`ops/reseau/routage-ens34.sh`, remis à chaque démarrage par le service
  `routage-ens34`) ; sinon le serveur répond en direct par ens33 et le pare-feu du routeur coupe la connexion.
- **Cron** (`ops/cron/mosip-bi`, heures en UTC = heure de Lomé) :
  - chaîne analytique toutes les 5 minutes ;
  - indicateurs en direct chaque minute ;
  - contrôle de santé toutes les 5 minutes ;
  - rattrapage de l'enrichissement deux fois par jour ;
  - fraîcheur des sources dbt toutes les heures.
- **Règle de publication** : si `dbt build` échoue (erreur ou test), rien n'est publié et l'API garde les chiffres
  précédents. Toute la publication se fait dans une seule transaction.
  Seules les lignes qui changent sont écrites dans `bi` (`sql/publication/synchroniser.sql`), et les tables que dbt
  reconstruit en entier sont `unlogged` : la BD traitement archive son journal (WAL), et l'ancienne publication en
  produisait environ 830 Go par jour (30/10/2026).
- **Journaux** : `/var/log/mosip-bi/*.log`. Les alertes du contrôle de santé sont dans `alertes.log`. `MAILTO` est vide
  dans le cron, donc personne n'est prévenu : à renseigner.

## Pas encore dans le dépôt

- La configuration des connecteurs des pré-inscriptions (sur le serveur seulement :
  `curl localhost:8083/connectors/<nom>/config`).
- Les scripts SQL 01, 02 et 11 de la BD traitement : création des schémas `lake`, `ods`, `ref`, `ind` et des rôles
  `ingest_writer`, `ods_writer`, `dbt_runner`, `publisher`, `publisher_ro`, `api_reader`.
