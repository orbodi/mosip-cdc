"""Sources enrichies par les jobs Spark (option --source des jobs) :

- prereg : pré-inscriptions (prereg.applicant_demographic), API de pré-inscription. Source par défaut, inchangée.
- inscriptions : inscriptions qui ont un NIU (regprc.rid_uin_link), ID Repository appelé avec le RID. Le NIU n'est
  jamais lu : rid_uin_link est capté sans sa colonne uin, et l'ID Repository est appelé par le RID.
"""
from dataclasses import dataclass

from commun import config, publication


@dataclass(frozen=True)
class Source:
    nom: str
    topic_entree: str           # topic Debezium des dossiers à enrichir
    champ_id: str               # identifiant du dossier dans payload.after (ou payload.before)
    operations: tuple           # opérations Debezium qui déclenchent un appel
    topic_enrichi: str
    topic_erreurs: str
    format: publication.Format
    point_de_reprise: str       # checkpoint du job en continu
    requete_rattrapage: str     # dossiers sans réponse de l'API, colonne « id », les plus récents d'abord

    def client(self, debit_max):
        from commun.api_client import ClientApi, ClientIdrepo
        return (ClientIdrepo if self.nom == "inscriptions" else ClientApi)(debit_max)


# Dossiers présents dans MOSIP et jamais enrichis. Les dossiers touchés dans la dernière heure sont laissés au job en
# continu, pour ne pas appeler l'API deux fois pour le même dossier.
PREREG = Source(
    nom="prereg",
    topic_entree=config.TOPIC_DOSSIERS,
    champ_id="prereg_id",
    operations=("c", "u"),
    topic_enrichi=config.TOPIC_ENRICHI,
    topic_erreurs=config.TOPIC_ERREURS,
    format=publication.PREREG,
    point_de_reprise="enrichissement-flux",
    requete_rattrapage="""
    SELECT p.prereg_id AS id
    FROM ods.applicant_demographic p
    LEFT JOIN ods.enrichissement e ON e.prereg_id = p.prereg_id
    WHERE e.prereg_id IS NULL
      AND coalesce(p.upd_dtimes, p.cr_dtimes) < (now() AT TIME ZONE 'UTC') - interval '1 hour'
    ORDER BY p.cr_dtimes DESC
""",
)

# Un lien créé = un NIU généré. Les liens de la dernière heure sont laissés au job en continu ; un lien que l'ID
# Repository ne connaît pas encore au moment du flux (identité pas encore écrite) est repris au rattrapage suivant.
INSCRIPTIONS = Source(
    nom="inscriptions",
    topic_entree=config.TOPIC_LIENS_NIU,
    champ_id="reg_id",
    operations=("c",),
    topic_enrichi=config.TOPIC_INSCRIPTIONS_ENRICHI,
    topic_erreurs=config.TOPIC_INSCRIPTIONS_ERREURS,
    format=publication.INSCRIPTION,
    point_de_reprise="enrichissement-inscriptions-flux",
    requete_rattrapage="""
    SELECT l.reg_id AS id
    FROM ods.regprc_rid_uin_link l
    LEFT JOIN ods.regprc_enrichissement e ON e.rid = l.reg_id
    WHERE e.rid IS NULL
      AND l.reg_id IS NOT NULL
      AND coalesce(l.__deleted, 'false') <> 'true'
      AND l.entry_date < (now() AT TIME ZONE 'UTC') - interval '1 hour'
    ORDER BY l.entry_date DESC
""",
)

SOURCES = {s.nom: s for s in (PREREG, INSCRIPTIONS)}
