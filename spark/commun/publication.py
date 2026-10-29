"""Publication dans Kafka au format JSON de Kafka Connect ({"schema", "payload"}),
attendu par les connecteurs JDBC qui rangent les résultats dans lake et ods.

Deux formats : pré-inscriptions (clé prereg_id, topics mosip.prereg.enrichissement*) et inscriptions qui ont un NIU
(clé rid, topics mosip.regprc.enrichissement*). Seuls les champs des schémas sont publiés : tout autre champ d'un
résultat est ignoré.
"""
import json
from dataclasses import dataclass

from commun import config

HORODATAGE = {"name": "org.apache.kafka.connect.data.Timestamp", "version": 1}


def _champ(nom, type_, optionnel=True, logique=None):
    champ = {"field": nom, "type": type_, "optional": optionnel}
    if logique:
        champ.update(logique)
    return champ


def _schema(nom, champs):
    return {"type": "struct", "name": nom, "optional": False, "fields": champs}


def _enveloppe(schema, valeurs):
    return json.dumps({"schema": schema, "payload": valeurs}, ensure_ascii=False, separators=(",", ":"))


def _valeurs(schema, donnees):
    return {c["field"]: donnees.get(c["field"]) for c in schema["fields"]}


@dataclass(frozen=True)
class Format:
    """Clé et schémas des messages d'une source."""
    cle: str
    schema_cle: dict
    schema_enrichi: dict
    schema_erreur: dict

    def enrichis(self, resultats, maintenant_ms):
        return [(_enveloppe(self.schema_cle, {self.cle: r[self.cle]}),
                 _enveloppe(self.schema_enrichi, _valeurs(self.schema_enrichi, {**r, "enrichi_le": maintenant_ms})))
                for r in resultats]

    def erreurs(self, resultats, maintenant_ms):
        return [(_enveloppe(self.schema_cle, {self.cle: r[self.cle]}),
                 _enveloppe(self.schema_erreur, _valeurs(self.schema_erreur, {
                     **r, "tentative": r.get("tentative", 1), "echec_le": maintenant_ms})))
                for r in resultats]


def _format(sujet, cle, champs):
    return Format(
        cle=cle,
        schema_cle=_schema(f"{sujet}.Key", [_champ(cle, "string", False)]),
        schema_enrichi=_schema(f"{sujet}.Value", [
            _champ(cle, "string", False),
            *champs,
            _champ("api_statut", "int32"),
            _champ("enrichi_le", "int64", False, HORODATAGE),
        ]),
        schema_erreur=_schema(f"{sujet}.erreurs.Value", [
            _champ(cle, "string", False),
            _champ("api_statut", "int32"),
            _champ("code_erreur", "string"),
            _champ("message", "string"),
            _champ("definitif", "boolean", False),
            _champ("tentative", "int32", False),
            _champ("echec_le", "int64", False, HORODATAGE),
        ]),
    )


# Pré-inscriptions : messages inchangés depuis la mise en service (tables lake.mosip_prereg_enrichissement et
# ods.enrichissement).
PREREG = _format("mosip.prereg.enrichissement", "prereg_id", [
    _champ("genre", "string"),
    _champ("nationalite", "string"),
    _champ("annee_naissance", "int32"),
    _champ("mois_naissance", "int32"),
    _champ("region_code", "string"),
    _champ("prefecture_code", "string"),
    _champ("commune_code", "string"),
    _champ("canton_code", "string"),
    _champ("localite_code", "string"),
])

# Inscriptions qui ont un NIU (ID Repository) : genre, nationalité, année et mois de naissance seulement
# (tables lake.mosip_regprc_enrichissement et ods.regprc_enrichissement).
INSCRIPTION = _format("mosip.regprc.enrichissement", "rid", [
    _champ("genre", "string"),
    _champ("nationalite", "string"),
    _champ("annee_naissance", "int32"),
    _champ("mois_naissance", "int32"),
])

# Noms historiques, gardés pour les pré-inscriptions
SCHEMA_CLE = PREREG.schema_cle
SCHEMA_ENRICHI = PREREG.schema_enrichi
SCHEMA_ERREUR = PREREG.schema_erreur


def messages_enrichis(resultats, maintenant_ms, format_=PREREG):
    return format_.enrichis(resultats, maintenant_ms)


def messages_erreurs(resultats, maintenant_ms, format_=PREREG):
    return format_.erreurs(resultats, maintenant_ms)


def publier(spark, topic, messages):
    if not messages:
        return
    (spark.createDataFrame(messages, "key string, value string")
          .write.format("kafka")
          .option("kafka.bootstrap.servers", config.KAFKA)
          .option("topic", topic)
          .save())
