# Impression et remise des cartes : chaîne de données et mise en service

Relevé et décisions : `docs/releve-impression.md` (02/11/2026). Indicateurs : section « Impression des cartes » de
`docs/indicateurs.md` (`mosip-bi-reporting`, branche `main`). Ce document couvre le lot 8a (capture) ; les calculs, le
contrat `bi` et la page viendront aux lots 8b et 8c.

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
