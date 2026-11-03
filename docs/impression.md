# Impression et remise des cartes : chaîne de données et mise en service

Relevé et décisions : `docs/releve-impression.md` (02/11/2026). Indicateurs : section « Impression des cartes » de
`docs/indicateurs.md` (`mosip-bi-reporting`, branche `main`). Ce document couvre le lot 8a (capture) et le lot 8b
(calculs, contrat `bi`, API) ; la page viendra au lot 8c.

```
mosip_regprc                        Kafka (1 partition par topic)                    BD traitement mosip_bi
printing_orders ─────────┐          mosip.regprc.printing_orders (compacté)        → ods.regprc_printing_orders        (upsert)
printing_shipped_cards ──┼ Debezium mosip.regprc.printing_shipped_cards (compacté) → ods.regprc_printing_shipped_cards (upsert)
printing_orders_details ─┘ mosip-   mosip.regprc.printing_orders_details (28 j)    → lake.mosip_regprc_printing_orders_details (journal)
                           regprc-impression-cdc (slot mosip_regprc_impression_cdc)
```

## Ce qui est capté

| Table MOSIP | Colonnes | Jamais lues |
|---|---|---|
| `printing_orders` | `id`, `rid`, `request_id`, `prc_status`, `entry_date`, `issuing_date` | `uin`, `citizen_fingers_count`, `center_name`, `request_type`, `target_request_type`, `priority`, `retry_count` |
| `printing_orders_details` | `id`, `request_id`, `status_code`, `reason_code`, `sub_status_code`, `cr_dtimes` | `details` (texte libre), `cr_by`, `source_app`, `status_ind` |
| `printing_shipped_cards` | `id`, `request_id`, `entry_date`, `delivery_status`, `delivery_mode`, `delivery_date` | `serial_number`, `logical_number`, `tracking_number`, `box_number`, `delivered_by`, `has_finger_biometrics_exception`, `status`, `delivery_site` |

Pas captées : `printing_processing_jobs` (l'historique donne mieux la même information) et la vue
`printing_orders_status` (à ne pas utiliser, décision du 02/11/2026).

**Snapshot allégé** : les commandes et les cartes en entier (≈ 6,2 M et 6,1 M de lignes) ; l'historique réduit aux
annulations et aux erreurs d'envoi à l'IDPS (≈ 300 000 lignes sur 22 M, `snapshot.select.statement.overrides`). Les
dates d'envoi (`issuing_date`), d'expédition (`entry_date` des cartes) et de remise (`delivery_date`) de tout
l'historique sont dans les deux autres tables. Après le snapshot, tous les nouveaux événements arrivent dans le lake
(≈ 70 000 par jour).

Le RID et `request_id` restent dans l'ODS et le lake ; ils ne sont jamais publiés vers `bi`. Le territoire se lit par
le RID (centre d'enrôlement, qui est aussi le lieu de remise).

## Mise en service du lot 8a

L'ordre compte : les tables d'arrivée et les topics avant les connecteurs, les connecteurs JDBC avant la source.

**DBA MOSIP** (accord du 02/11/2026)
1. `sql/mosip/05_prerequis_impression.sql` : partie A, renvoyer les résultats (18 colonnes, replica identity `d`,
   trois tables dans `dbz_publication`, nombre de lignes du snapshot) ; puis partie B1 (droits `SELECT` sur les seules
   colonnes captées). Convenir du créneau creux du snapshot (≈ 12,5 M de lignes).

**Serveur pipeline**
2. `git pull` de `mosip-cdc` sous le verrou de la chaîne analytique
   (`flock /tmp/mosip-analytique.lock git -C /data/mosip-cdc pull`). Rien ne change dans les calculs ;
   `scripts/check-health.sh` signale les nouveaux connecteurs absents jusqu'à l'étape 6.

**BD traitement**
3. `ods_writer` : `sql/traitement/21_ods_regprc_impression.sql` ; `ingest_writer` :
   `sql/traitement/22_lake_regprc_impression.sql`.

**Kafka**
4. Topics, dans l'interface Kafka ou par `kafka/topics.sh` (réglages de `topics.sh`) : `mosip.regprc.printing_orders`
   et `mosip.regprc.printing_shipped_cards` (compactés, `min.compaction.lag.ms=86400000`),
   `mosip.regprc.printing_orders_details` (28 jours) et `__debezium-heartbeat.mosip_regprc_impression` (compacté). Les
   vérifier en ligne de commande, l'interface masquant ceux qui commencent par `__` :
   `docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list | grep -E 'printing|impression'`.
5. Connecteurs JDBC, dans l'interface Kafka (nom = nom du fichier de `kafka/connecteurs/`, configuration = son contenu,
   mot de passe reporté) : `ods-regprc-printing-orders`, `ods-regprc-printing-shipped-cards`,
   `lake-regprc-printing-orders-details`. Ils attendent les messages.
6. **Au créneau convenu** : connecteur source `mosip-regprc-impression-cdc` (hôte et mot de passe reportés). Le
   snapshot démarre aussitôt ; le slot `mosip_regprc_impression_cdc` reste inactif pendant le snapshot, puis passe
   actif.

**Vérifier**
7. Pendant et après le snapshot :
   ```sql
   SELECT count(*) FROM ods.regprc_printing_orders;           -- ≈ 6 180 000
   SELECT count(*) FROM ods.regprc_printing_shipped_cards;    -- ≈ 6 090 000
   SELECT status_code, count(*) FROM lake.mosip_regprc_printing_orders_details GROUP BY 1;
   -- snapshot : NEW-PRINT-CANCELED ≈ 693, PRINT-REQUEST-ERR ≈ 302 800 ; ensuite, tous les codes arrivent
   SELECT prc_status, count(*) FROM ods.regprc_printing_orders GROUP BY 1;   -- OK, NEW, KO (relevé du 02/11/2026)
   ```
   Retard du slot : `scripts/check-health.sh` (moins de 1 Go). Aucune colonne `uin`, `details`, `serial_number` ni
   `delivered_by` dans l'ODS, le lake ni les messages Kafka.

Retour arrière : supprimer le connecteur source, puis le slot (`SELECT pg_drop_replication_slot('mosip_regprc_impression_cdc');`,
DBA) ; supprimer les trois connecteurs JDBC. Les tables d'arrivée et les topics peuvent rester : rien ne les lit avant
le lot 8b.

## Points d'attention

- **Slot non borné** (EDB 12, pas de `max_slot_wal_keep_size`) : comme les trois autres slots, son retard est surveillé
  par `scripts/check-health.sh`. Il avance même quand l'impression est calme : `dbz_publication` contient aussi
  `registration`, dont Debezium reçoit les changements, les écarte et fait avancer le slot à chaque battement.
- **Compter des commandes, pas des événements** (lot 8b) : certaines cartes sont mises en boîte plusieurs fois, et
  certaines remises enregistrées deux fois (relevé, étape 2).

## Lot 8b : calculs, contrat `bi` et API (03/11/2026)

```
ods.regprc_printing_orders ─────────┐
ods.regprc_printing_shipped_cards ──┼─ dwh.suivi_carte ─┬─ dm_impression.fait_demande_impression_jour ─┐
lake.mosip_regprc_printing_orders_  │  (une ligne par   ├─ dm_impression.fait_carte_jour ──────────────┤ publier-   bi.* (V15)
  details (annulations) ────────────┤   commande,       ├─ dm_impression.fait_delai_carte_jour ────────┼ indicateurs → API
ods.regprc_rid_uin_link (NIU) ──────┘   incrémental)    ├─ dm_impression.fait_annulation_impression_jour┤ .sh        /api/v1/cartes
                                                        └─ dm_impression.fraicheur_impression ─────────┘            (source « cartes »)
```

**Règles** (dictionnaire `docs/indicateurs.md` de `mosip-bi-reporting`, section Impression des cartes) :
- une ligne par commande, première date de chaque jalon : on compte des commandes, jamais des événements ;
- deux lectures « cohorte » : les commandes au jour de réception (`entry_date`), dans leur statut d'aujourd'hui
  (demandes, en attente `NEW`, rejetées `KO`, annulées à part) ; les cartes au jour d'expédition, remises ou non
  aujourd'hui (expédiées, remises par mode, à remettre, délai du NIU à la remise) ;
- l'ancienneté des cartes à remettre se lit dans le jour d'expédition : l'API la calcule à la lecture, sans stock ;
- territoire : centre du RID (cinq premiers chiffres), résolu en `bi.zone` à la publication ;
- correspondances : `seeds/ref_impression_statuts.csv`, `ref_impression_modes_remise.csv`,
  `ref_impression_motifs_annulation.csv` ; un code inconnu compte en « non classée », mode « autre » ou motif
  `NON_REPERTORIE`, et lève une alerte.

**Contrôles** (tests dbt bloquants, et contraintes de `bi`) : statuts = demandes, annulées ≤ demandes
(`assert_impression_statuts_egal_demandes`) ; remises + à remettre = expédiées, modes = remises
(`assert_impression_remises_egal_expediees`) ; expédiées ≤ demandes par centre
(`assert_impression_expediees_parmi_demandes`) ; motifs = annulées (`assert_impression_annulations_egal_motifs`) ;
histogramme des délais ≤ remises (`assert_impression_delais_parmi_remises`). Alertes, sur les seules commandes du
dernier passage : anomalies connues (`assert_impression_anomalies_cartes`), carte sans commande
(`assert_impression_cartes_sans_commande`), codes inconnus, centre non référencé.

**API** (`mosip-bi-reporting`, branche `dashboard`, package `cartes`) : `GET /api/v1/cartes/impression`, `/semaines`,
`/territoire`, `/attente`, `/centres`, `/annulations` (paramètres `du`, `au`, `zone`).

### Mise en service du lot 8b

L'ordre compte : la migration V15 avant le script de publication qui écrit ses tables, sinon toute la publication
échoue (comme V14 le 02/11/2026).

1. **API** (`mosip-bi-reporting`, branche `dashboard`) : `git pull`, tests, redémarrage ; Flyway applique V15 (quatre
   tables vides). Vérifier : `select version, success from flyway_schema_history where version = '15';`
2. **Droits** (bi_owner) :
   `PGPASSWORD="$BI_OWNER_PASSWORD" psql -h 172.16.44.108 -U bi_owner -d mosip_bi -f sql/traitement/23_droits_bi_impression.sql`
   (depuis un clone à jour de `mosip-cdc` ; le script ne fait que des GRANT).
3. **Pipeline** : `flock /tmp/mosip-analytique.lock git -C /data/mosip-cdc pull`. Le passage suivant construit
   `dwh.suivi_carte` en entier (6,2 M de commandes, premier passage plus long), puis les faits, puis publie.
4. **Vérifier**, après le premier passage publié (en `api_reader` ou `dbt_runner`) :
   ```sql
   SELECT sum(demandes), sum(en_attente), sum(rejetees), sum(annulees) FROM bi.fait_demande_impression_jour;
   -- ≈ 6 186 000, ≈ 2 250, 8, 693
   SELECT sum(expediees), sum(remises), sum(a_remettre) FROM bi.fait_carte_jour;
   -- ≈ 6 088 000, ≈ 4 643 000, ≈ 1 445 000 (relevé du 02/11/2026)
   SELECT source, premiere_donnee, derniere_donnee FROM bi.source_fraicheur WHERE source = 'cartes';
   ```
   et `curl -s http://localhost:8080/api/v1/cartes/impression | jq` (API du serveur).
5. **Requête 5, vérification complète des cartes sans commande** (`dbt_runner`, à lancer à la mise en service puis de
   temps en temps ; l'alerte dbt ne regarde que les cartes récentes) :
   ```sql
   SELECT count(*) FROM ods.regprc_printing_shipped_cards c
   WHERE NOT EXISTS (SELECT 1 FROM ods.regprc_printing_orders o WHERE o.request_id = c.request_id);   -- 0 attendu
   ```

Retour arrière : revenir au commit précédent de `mosip-cdc` (la publication n'écrit plus les tables V15, qui restent
en place) ; V15 est additive et n'a pas à être défaite.
