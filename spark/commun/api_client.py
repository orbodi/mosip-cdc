"""Clients des API MOSIP d'enrichissement.

- ClientApi : API de pré-inscription, un dossier par prereg_id. Champs extraits : genre, nationalité, année et mois de
  naissance, codes de résidence.
- ClientIdrepo : ID Repository (/idrepository/v1/identity/idvid/{RID}), une identité par RID d'une inscription qui a
  un NIU. Champs extraits : genre, nationalité, année et mois de naissance. Appelé avec le RID, jamais avec le NIU.

Le reste de la réponse (noms, noms des parents, téléphone, NIU, numéro de pièce, date de naissance complète, lieu de
naissance, profession...) n'est jamais conservé, renvoyé ni journalisé. L'identifiant appelé n'est jamais journalisé.
"""
import datetime as dt
import logging
import os
import re
import ssl
import threading
import time

import httpx

from commun import config

log = logging.getLogger("api_client")

URL_AUTH = "/v1/authmanager/authenticate/clientidsecretkey"
URL_DOSSIER = "/preregistration/v1/applications/{}"
URL_IDENTITE = "/idrepository/v1/identity/idvid/{}"

# Colonne du BI -> champ de résidence de l'API
CHAMPS_RESIDENCE = {
    "region_code": "region",
    "prefecture_code": "prefecture",
    "commune_code": "commun",
    "canton_code": "canton",
    "localite_code": "locality",
}
COLONNES = ["genre", "nationalite", "annee_naissance", "mois_naissance", *CHAMPS_RESIDENCE]
COLONNES_INSCRIPTION = ["genre", "nationalite", "annee_naissance", "mois_naissance"]


class Limiteur:
    """Plafond de débit partagé par tous les threads : au plus `par_seconde` appels par seconde."""

    def __init__(self, par_seconde):
        self._intervalle = 1.0 / par_seconde
        self._prochain = time.monotonic()
        self._verrou = threading.Lock()

    def attendre(self):
        with self._verrou:
            maintenant = time.monotonic()
            depart = max(self._prochain, maintenant)
            self._prochain = depart + self._intervalle
        if depart > maintenant:
            time.sleep(depart - maintenant)


def _valeur(identite, champ):
    """Valeur d'un champ : liste [{"language", "value"}] ou simple chaîne."""
    v = identite.get(champ)
    if isinstance(v, list):
        for element in v:
            if isinstance(element, dict) and element.get("value") not in (None, ""):
                return str(element["value"])
        return None
    return None if v in (None, "") else str(v)


def extraire(identite):
    """Champs utiles d'un dossier. Tout le reste de `identite` est ignoré."""
    resultat = {colonne: None for colonne in COLONNES}
    resultat["genre"] = _valeur(identite, "gender")
    resultat["nationalite"] = _valeur(identite, "nationality")
    for colonne, champ in CHAMPS_RESIDENCE.items():
        resultat[colonne] = _valeur(identite, champ)

    naissance = _valeur(identite, "dateOfBirth")
    if naissance:
        resultat["annee_naissance"], resultat["mois_naissance"] = annee_mois(
            naissance, mois_inconnu=identite.get("hasntMonthOfBirthFlag") == "Y")
    return resultat


def extraire_inscription(identite):
    """Champs utiles d'une identité de l'ID Repository : genre, nationalité, année et mois de naissance."""
    tout = extraire(identite)
    return {colonne: tout[colonne] for colonne in COLONNES_INSCRIPTION}


def annee_mois(texte, mois_inconnu=False):
    """Année et mois d'une date de naissance, quel que soit son format :
    AAAA/MM/JJ, AAAA-MM-JJ, JJ/MM/AAAA, AAAA-MM, AAAA seule, avec ou sans heure. Le jour est ignoré."""
    morceaux = re.findall(r"\d+", str(texte).split("T")[0])
    annee = next((int(m) for m in morceaux if len(m) == 4), None)
    if annee is None or not 1900 <= annee <= dt.date.today().year:
        return None, None
    mois = None
    if not mois_inconnu:
        if len(morceaux) == 3 and len(morceaux[1]) <= 2:          # le mois est au milieu (A/M/J ou J/M/A)
            mois = int(morceaux[1])
        elif len(morceaux) == 2 and len(morceaux[0]) == 4:        # AAAA-MM
            mois = int(morceaux[1])
        if mois is not None and not 1 <= mois <= 12:
            mois = None
    return annee, mois


def _echec(cle, identifiant, api_statut, code, message="", definitif=False):
    return {"ok": False, cle: identifiant, "api_statut": api_statut,
            "code_erreur": code, "message": (message or "")[:200], "definitif": definitif}


class ClientApi:
    """Appels à l'API de pré-inscription, partagés entre threads : authentification, plafond de débit, nouvelles
    tentatives. Les sous-classes changent l'adresse, les identifiants, la clé et l'extraction."""

    CLE = "prereg_id"
    URL = URL_DOSSIER

    def __init__(self, debit_max, url=None, app_id=None, client_id=None, secret_key=None):
        self._app_id = app_id or config.API_APP_ID
        self._client_id = client_id or config.API_CLIENT_ID
        self._secret_key = secret_key or config.API_SECRET_KEY
        if config.API_TLS_VERIFY:
            if not os.path.isfile(config.API_CA_FILE):
                raise SystemExit(
                    f"Certificat de l'autorité introuvable : {config.API_CA_FILE}. "
                    "Le déposer dans compose/certs/ca-eid.crt, ou, temporairement, API_TLS_VERIFY=false.")
            verification = ssl.create_default_context(cafile=config.API_CA_FILE)
        else:
            log.warning("vérification du certificat de l'API désactivée (API_TLS_VERIFY=false)")
            verification = False
        self._http = httpx.Client(
            base_url=url or config.API_URL, timeout=config.API_DELAI_S, verify=verification,
            limits=httpx.Limits(max_connections=64, max_keepalive_connections=64))
        self._limiteur = Limiteur(debit_max)
        self._verrou_auth = threading.Lock()
        self._jeton = None
        self._generation = 0
        self._authentifie_le = 0.0
        self._authentifier()

    # ---------- Authentification ----------

    def _authentifier(self):
        maintenant = dt.datetime.now(dt.timezone.utc)
        corps = {
            "id": "string", "version": "1.0", "metadata": {},
            "requesttime": maintenant.strftime("%Y-%m-%dT%H:%M:%S.") + f"{maintenant.microsecond // 1000:03d}Z",
            "request": {"appId": self._app_id, "clientId": self._client_id, "secretKey": self._secret_key},
        }
        r = self._http.post(URL_AUTH, json=corps)
        jeton = r.cookies.get("Authorization")
        erreurs = r.json().get("errors") if r.headers.get("content-type", "").startswith("application/json") else None
        if r.status_code != 200 or erreurs or not jeton:
            code = erreurs[0].get("errorCode") if erreurs else f"HTTP {r.status_code}"
            raise RuntimeError(f"Authentification à l'API refusée : {code}")
        self._http.cookies.clear()           # le jeton est envoyé explicitement, jamais par le magasin de cookies
        self._jeton = jeton
        self._generation += 1
        self._authentifie_le = time.monotonic()
        log.info("authentifié auprès de l'API (génération %s)", self._generation)

    def _jeton_courant(self):
        if time.monotonic() - self._authentifie_le > config.JETON_RENOUVELLEMENT_S:
            self._renouveler(self._generation)
        return self._jeton, self._generation

    def _renouveler(self, generation_utilisee):
        """Une seule réauthentification, même si plusieurs threads reçoivent un refus en même temps."""
        with self._verrou_auth:
            if self._generation == generation_utilisee:
                self._authentifier()

    # ---------- Appel d'un dossier ----------

    def _identite(self, donnees):
        """Identité contenue dans la réponse (dictionnaire), ou None."""
        return ((donnees.get("response") or {}).get("demographicDetails") or {}).get("identity")

    def _extraire(self, identite):
        return extraire(identite)

    def enrichir(self, identifiant):
        """Renvoie {"ok": True, <clé>, api_statut, champs utiles} ou un échec décrit sans donnée personnelle."""
        cle = self.CLE
        resultat = _echec(cle, identifiant, None, "NON_TENTE")
        for essai in range(config.API_ESSAIS):
            if essai:
                time.sleep(2 ** (essai - 1))                     # 1 s, 2 s...
            self._limiteur.attendre()
            jeton, generation = self._jeton_courant()
            try:
                r = self._http.get(self.URL.format(identifiant),
                                   headers={"Cookie": f"Authorization={jeton}"})
            except httpx.HTTPError as e:                          # délai dépassé, connexion refusée...
                resultat = _echec(cle, identifiant, None, type(e).__name__)
                continue
            self._http.cookies.clear()

            if r.status_code in (401, 403):
                self._renouveler(generation)
                resultat = _echec(cle, identifiant, r.status_code, f"HTTP {r.status_code}")
                continue
            if r.status_code == 429 or r.status_code >= 500:
                resultat = _echec(cle, identifiant, r.status_code, f"HTTP {r.status_code}")
                continue
            if r.status_code != 200:
                return _echec(cle, identifiant, r.status_code, f"HTTP {r.status_code}", definitif=True)
            try:
                donnees = r.json()
            except ValueError:
                resultat = _echec(cle, identifiant, 200, "REPONSE_ILLISIBLE")
                continue

            erreurs = donnees.get("errors") or []
            if erreurs:
                code = str(erreurs[0].get("errorCode") or "ERREUR_API")
                if code.startswith("KER-ATH"):                    # jeton refusé ou expiré
                    self._renouveler(generation)
                    resultat = _echec(cle, identifiant, 200, code)
                    continue
                return _echec(cle, identifiant, 200, code, str(erreurs[0].get("message") or ""), definitif=True)

            identite = self._identite(donnees)
            if not isinstance(identite, dict):
                return _echec(cle, identifiant, 200, "SANS_IDENTITE", definitif=True)
            return {"ok": True, cle: identifiant, "api_statut": 200, **self._extraire(identite)}
        return resultat


class ClientIdrepo(ClientApi):
    """ID Repository de MOSIP : identité d'une inscription qui a un NIU, appelée par son RID. Mêmes passerelle et
    authentification que la pré-inscription, avec les identifiants IDREPO_* de compose/.env (à défaut, ceux de API_*).
    Le message d'erreur de MOSIP n'est pas gardé : il peut reprendre l'identifiant appelé."""

    CLE = "rid"
    URL = URL_IDENTITE

    def __init__(self, debit_max):
        super().__init__(debit_max, url=config.IDREPO_URL, app_id=config.IDREPO_APP_ID,
                         client_id=config.IDREPO_CLIENT_ID, secret_key=config.IDREPO_SECRET_KEY)

    def _identite(self, donnees):
        return (donnees.get("response") or {}).get("identity")

    def _extraire(self, identite):
        return extraire_inscription(identite)

    def enrichir(self, identifiant):
        resultat = super().enrichir(identifiant)
        if not resultat["ok"]:
            resultat["message"] = ""
        return resultat
