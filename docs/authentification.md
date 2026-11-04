# Authentifications : chaîne de données et mise en service

Relevé et décisions : `docs/releve-authentification.md` (03 et 04/11/2026). Indicateurs : section « Authentifications »
de `docs/indicateurs.md` (`mosip-bi-reporting`, branche `main`). Ce document couvre le lot 9a (capture) ; les calculs,
le contrat `bi` et l'API viendront au lot 9b, la page au lot 9c.

```
mosip_ida                  Kafka (1 partition par topic)               BD traitement mosip_bi
auth_transaction ──┐       mosip.ida.auth_transaction (compacté)    → ods.ida_auth_transaction (upsert)
otp_transaction  ──┴ Debezium mosip.ida.otp_transaction (compacté)  → ods.ida_otp_transaction  (upsert)
                     mosip-ida-cdc (slot mosip_ida_cdc, publication dbz_publication de mosip_ida)
```

## Ce qui est capté

| Table MOSIP | Colonnes | Jamais lues |
|---|---|---|
| `auth_transaction` | `id`, `cr_dtimes`, `auth_type_code`, `status_code`, `status_comment`, `requested_entity_type`, `requested_entity_id`, `requested_entity_name`, `is_deleted` | `ref_id`, `token_id`, `static_tkn_id`, `request_signature`, `response_signature`, `request_trn_id`, `request_dtimes`, `response_dtimes`, `lang_code`, `ref_id_type`, `cr_by`, `upd_by`, `upd_dtimes`, `del_dtimes` |
| `otp_transaction` | `id`, `status_code`, `cr_dtimes`, `expiry_dtimes`, `is_deleted` | `ref_id`, `otp_hash`, `generated_dtimes`, `validation_retry_count`, `lang_code`, `cr_by`, `upd_by`, `upd_dtimes`, `del_dtimes` |

Aucune autre table de `mosip_ida`. `status_comment` (messages fixes d'IDA, relevé sur 30 jours) reste dans l'ODS :
seul un code de motif sera publié vers `bi` (lot 9b), comme `registration.status_comment`. Un message inconnu comptera
en « motif non répertorié », avec une alerte dbt.

Les deux topics sont **compactés** (dernier état de chaque ligne ; l'ODS se reconstruit depuis le topic) : une
authentification ne change plus après son écriture, un code OTP passe de `active` à `used`.

## Mise en service du lot 9a

L'ordre compte : les tables d'arrivée et les topics avant les connecteurs, les connecteurs JDBC avant la source.

**DBA MOSIP**
1. `sql/mosip/06_prerequis_ida.sql` : partie A, renvoyer les résultats (14 colonnes, replica identity `d`,
   publications de `mosip_ida`, droits actuels, activité par heure, volumes) ; puis partie B1 (droits `SELECT` sur les
   seules colonnes captées) et B2 (publication). Convenir du créneau creux du snapshot (≈ 3,25 M de lignes, parcours
   des 12 Go de `auth_transaction` une fois).

**Serveur pipeline**
2. `git pull` de `mosip-cdc` sous le verrou de la chaîne analytique
   (`flock /tmp/mosip-analytique.lock git -C /data/mosip-cdc pull`). Rien ne change dans les calculs ;
   `scripts/check-health.sh` signale les nouveaux connecteurs absents jusqu'à l'étape 6.

**BD traitement**
3. `ods_writer` : `sql/traitement/25_ods_ida.sql`.

**Kafka**
4. Topics, dans l'interface Kafka ou par `kafka/topics.sh` : `mosip.ida.auth_transaction` et
   `mosip.ida.otp_transaction` (compactés, `min.compaction.lag.ms=86400000`), `__debezium-heartbeat.mosip_ida`
   (compacté). Les vérifier en ligne de commande, l'interface masquant ceux qui commencent par `__` :
   `docker exec mosip-cdc-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list | grep ida`.
5. Connecteurs JDBC, dans l'interface Kafka (nom = nom du fichier de `kafka/connecteurs/`, configuration = son contenu,
   mot de passe reporté) : `ods-ida-auth-transaction`, `ods-ida-otp-transaction`. Ils attendent les messages.
6. **Au créneau convenu** : connecteur source `mosip-ida-cdc` (hôte et mot de passe reportés). Le snapshot démarre
   aussitôt.

**Vérifier**
7. Pendant et après le snapshot (en `dbt_runner`) :
   ```sql
   SELECT count(*) FROM ods.ida_auth_transaction;    -- ≈ 3 250 000
   SELECT count(*) FROM ods.ida_otp_transaction;     -- ≈ 84 000
   SELECT requested_entity_id, status_code, count(*) FROM ods.ida_auth_transaction
   WHERE cr_dtimes >= now() - interval '30 days' GROUP BY 1, 2 ORDER BY 1, 2;   -- comme le relevé
   SELECT status_code, count(*) FROM ods.ida_otp_transaction GROUP BY 1;        -- used ≈ 50 800, active ≈ 33 100
   ```
   Retard du slot : `scripts/check-health.sh` (moins de 1 Go). Aucune colonne `ref_id`, `token_id`, signature ni
   `otp_hash` dans l'ODS ni dans les messages Kafka.

Retour arrière : supprimer le connecteur source, puis le slot (`SELECT pg_drop_replication_slot('mosip_ida_cdc');`,
DBA) ; supprimer les deux connecteurs JDBC. Les tables d'arrivée et les topics peuvent rester : rien ne les lit avant
le lot 9b.

## Points d'attention

- **Nouvelle base, nouveau slot** : une publication appartient à une base, celle de `mosip_regprc` ne sert pas ici.
  Le slot de `mosip_ida` n'avance que quand l'une des tables publiées change : les vérifications du traitement des
  paquets en font en continu, mais la partie A du script vérifie qu'aucune heure ne reste vide. Sinon, table de
  battement de cœur à prévoir. Slot non borné (EDB 12) : retard surveillé par `scripts/check-health.sh`.
- **Snapshot** : le parcours des 12 Go de `auth_transaction` (signatures comprises, même si elles ne sont pas lues
  par le connecteur) pèse sur la base MOSIP : créneau creux.
