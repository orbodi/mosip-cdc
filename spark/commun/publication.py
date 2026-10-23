"""Publication dans Kafka au format JSON de Kafka Connect ({"schema", "payload"}),
attendu par les connecteurs JDBC qui rangent les résultats dans lake et ods."""
import json

from commun import config

HORODATAGE = {"name": "org.apache.kafka.connect.data.Timestamp", "version": 1}


def _champ(nom, type_, optionnel=True, logique=None):
    champ = {"field": nom, "type": type_, "optional": optionnel}
    if logique:
        champ.update(logique)
    return champ


def _schema(nom, champs):
    return {"type": "struct", "name": nom, "optional": False, "fields": champs}


SCHEMA_CLE = _schema("mosip.prereg.enrichissement.Key", [_champ("prereg_id", "string", False)])

SCHEMA_ENRICHI = _schema("mosip.prereg.enrichissement.Value", [
    _champ("prereg_id", "string", False),
    _champ("genre", "string"),
    _champ("nationalite", "string"),
    _champ("annee_naissance", "int32"),
    _champ("mois_naissance", "int32"),
    _champ("region_code", "string"),
    _champ("prefecture_code", "string"),
    _champ("commune_code", "string"),
    _champ("canton_code", "string"),
    _champ("localite_code", "string"),
    _champ("api_statut", "int32"),
    _champ("enrichi_le", "int64", False, HORODATAGE),
])

SCHEMA_ERREUR = _schema("mosip.prereg.enrichissement.erreurs.Value", [
    _champ("prereg_id", "string", False),
    _champ("api_statut", "int32"),
    _champ("code_erreur", "string"),
    _champ("message", "string"),
    _champ("definitif", "boolean", False),
    _champ("tentative", "int32", False),
    _champ("echec_le", "int64", False, HORODATAGE),
])


def _enveloppe(schema, valeurs):
    return json.dumps({"schema": schema, "payload": valeurs}, ensure_ascii=False, separators=(",", ":"))


def _valeurs(schema, donnees):
    return {c["field"]: donnees.get(c["field"]) for c in schema["fields"]}


def messages_enrichis(resultats, maintenant_ms):
    return [(_enveloppe(SCHEMA_CLE, {"prereg_id": r["prereg_id"]}),
             _enveloppe(SCHEMA_ENRICHI, _valeurs(SCHEMA_ENRICHI, {**r, "enrichi_le": maintenant_ms})))
            for r in resultats]


def messages_erreurs(resultats, maintenant_ms):
    return [(_enveloppe(SCHEMA_CLE, {"prereg_id": r["prereg_id"]}),
             _enveloppe(SCHEMA_ERREUR, _valeurs(SCHEMA_ERREUR, {
                 **r, "tentative": r.get("tentative", 1), "echec_le": maintenant_ms})))
            for r in resultats]


def publier(spark, topic, messages):
    if not messages:
        return
    (spark.createDataFrame(messages, "key string, value string")
          .write.format("kafka")
          .option("kafka.bootstrap.servers", config.KAFKA)
          .option("topic", topic)
          .save())
