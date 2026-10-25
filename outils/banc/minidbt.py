"""Mini dbt pour le banc de test : rend les modèles (ref, source, config, is_incremental, this, var) et les exécute
sur PostgreSQL avec psql. Matérialisations table / incremental (append, delete+insert), seeds, grants, index,
tests génériques (not_null, unique, accepted_values, relationships) et tests singuliers.

Usage : python3 minidbt.py <dossier dbt> <dsn psql> [--full-refresh]
"""
import csv
import os
import re
import subprocess
import sys

import jinja2
import yaml

DBT = sys.argv[1]
DSN = sys.argv[2]
FULL = "--full-refresh" in sys.argv


def psql(sql, valeur=False):
    r = subprocess.run(["psql", DSN, "-v", "ON_ERROR_STOP=1", "-Atq", "-c", sql], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"psql : {r.stderr.strip()}\n--- SQL ---\n{sql}")
    return r.stdout.strip() if valeur else None


projet = yaml.safe_load(open(f"{DBT}/dbt_project.yml"))
VARS = projet.get("vars", {})


def config_dossier(arbre, parties):
    """Configuration +clé héritée le long des dossiers (models: mosip_bi: dwh: …), puis par nom de modèle."""
    cfg, noeud = {}, arbre
    for p in parties:
        if not isinstance(noeud, dict) or p not in noeud:
            break
        noeud = noeud[p]
        cfg.update({k[1:]: v for k, v in noeud.items() if k.startswith("+")})
    return cfg


# ---------------------------------------------------------------- inventaire
noeuds = {}
for racine, _, fichiers in os.walk(f"{DBT}/models"):
    for f in fichiers:
        if f.endswith(".sql"):
            nom = f[:-4]
            rel = os.path.relpath(os.path.join(racine, f), f"{DBT}/models").split(os.sep)
            cfg = {"materialized": "view", "schema": "dwh"}
            cfg.update(config_dossier(projet["models"], ["mosip_bi", *rel[:-1], nom]))
            noeuds[nom] = {"type": "model", "sql": open(os.path.join(racine, f)).read(), "cfg": cfg}
seeds = {}
for f in os.listdir(f"{DBT}/seeds"):
    if f.endswith(".csv"):
        nom = f[:-4]
        cfg = {"schema": "dwh"}
        cfg.update(config_dossier(projet.get("seeds", {}), ["mosip_bi", nom]))
        seeds[nom] = cfg

class Relation(str):
    pass


def relation(nom):
    cfg = noeuds[nom]["cfg"] if nom in noeuds else seeds[nom]
    r = Relation(f'"{cfg["schema"]}"."{nom}"')
    r.schema, r.identifier = cfg["schema"], nom
    return r


def existe(nom):
    cfg = noeuds[nom]["cfg"]
    return psql(f"select to_regclass('{cfg['schema']}.{nom}') is not null", True) == "t"


# ---------------------------------------------------------------- rendu
def rendre(sql, nom=None, incremental=False):
    capture = {}
    env = jinja2.Environment(undefined=jinja2.StrictUndefined)
    ctx = {
        "config": lambda **kw: capture.update(kw) or "",
        "ref": lambda n: relation(n),
        "source": lambda s, t: f'"{s}"."{t}"',
        "is_incremental": lambda: incremental,
        "this": relation(nom) if nom else None,
        "var": lambda n, d=None: VARS.get(n, d),
        "env_var": lambda n, d=None: os.environ.get(n, d),
    }
    return env.from_string(sql).render(**ctx), capture


def dependances(sql):
    return set(re.findall(r"ref\(\s*'([^']+)'\s*\)", sql))


ordre, vus = [], set()
def visiter(n):
    if n in vus or n not in noeuds:
        return
    vus.add(n)
    for d in dependances(noeuds[n]["sql"]):
        visiter(d)
    ordre.append(n)
for n in sorted(noeuds):
    visiter(n)


# ---------------------------------------------------------------- seeds
def type_colonne(valeurs):
    v = [x for x in valeurs if x != ""]
    if v and all(re.fullmatch(r"-?\d+", x) for x in v):
        return "integer"
    if v and all(x.lower() in ("true", "false") for x in v):
        return "boolean"
    return "text"

for nom, cfg in sorted(seeds.items()):
    lignes = list(csv.reader(open(f"{DBT}/seeds/{nom}.csv", encoding="utf-8")))
    entete, donnees = lignes[0], lignes[1:]
    types = cfg.get("column_types", {})
    cols = [(c, types.get(c) or type_colonne([l[i] for l in donnees])) for i, c in enumerate(entete)]
    psql(f'create schema if not exists "{cfg["schema"]}"; drop table if exists {relation(nom)} cascade; '
         f'create table {relation(nom)} ({", ".join(f"{c} {t}" for c, t in cols)});')
    for l in donnees:
        vals = ", ".join("null" if x == "" else "'" + x.replace("'", "''") + "'" for x in l)
        psql(f"insert into {relation(nom)} values ({vals});")
    print(f"seed   {nom} : {len(donnees)} lignes")


# ---------------------------------------------------------------- modèles
for nom in ordre:
    n = noeuds[nom]
    cfg = dict(n["cfg"])
    _, cap = rendre(n["sql"], nom, False)
    cfg.update(cap)
    rel = relation(nom)
    schema = cfg["schema"]
    psql(f'create schema if not exists "{schema}";')
    incr = cfg["materialized"] == "incremental" and not FULL and existe(nom)
    sql, _ = rendre(n["sql"], nom, incr)
    if incr:
        tmp = f'"{schema}"."{nom}__tmp"'
        psql(f"drop table if exists {tmp}; create table {tmp} as {sql};")
        # Une seule commande, donc une seule transaction, comme dbt : un insert refusé (index unique) annule le delete.
        supprimer = ""
        if cfg.get("incremental_strategy") == "delete+insert":
            k = cfg["unique_key"]
            supprimer = f"delete from {rel} t using {tmp} s where t.{k} = s.{k}; "
        psql(f"{supprimer}insert into {rel} select * from {tmp}; drop table {tmp};")
        mode = f"incremental ({cfg.get('incremental_strategy')})"
    else:
        genre = psql(f"select relkind from pg_class where oid = to_regclass('{schema}.{nom}')", True)
        if genre:
            psql(f"drop {'view' if genre == 'v' else 'table'} {rel} cascade;")
        objet = "view" if cfg["materialized"] == "view" else "table"
        psql(f"create {objet} {rel} as {sql};")
        for i, idx in enumerate(cfg.get("indexes", []) if cfg["materialized"] != "view" else []):
            u = "unique " if idx.get("unique") else ""
            psql(f'create {u}index on {rel} ({", ".join(idx["columns"])});')
        mode = cfg["materialized"]
    hooks = cfg.get("post-hook", [])
    for h in [hooks] if isinstance(hooks, str) else hooks:
        psql(rendre(h, nom)[0])
    for role in cfg.get("grants", {}).get("select", []):
        psql(f"grant select on {rel} to {role};")
    print(f"modèle {nom} [{mode}] : {psql(f'select count(*) from {rel}', True)} lignes")


# ---------------------------------------------------------------- tests
echecs = alertes = 0
def verdict(libelle, sql, severite="error"):
    global echecs, alertes
    n = int(psql(f"select count(*) from ({sql}) t", True))
    if n == 0:
        print(f"  ok     {libelle}")
    elif severite == "warn":
        alertes += 1
        print(f"  ALERTE {libelle} : {n}")
    else:
        echecs += 1
        print(f"  ÉCHEC  {libelle} : {n}")

proprietes = [os.path.join(r, f) for d in ("models", "seeds") for r, _, fs in os.walk(f"{DBT}/{d}") for f in fs
              if f.endswith(".yml") and f != "sources.yml"]
for chemin in proprietes:
    doc = yaml.safe_load(open(chemin)) or {}
    for m in doc.get("models", []) + doc.get("seeds", []):
        if m["name"] not in noeuds and m["name"] not in seeds:
            continue
        rel = relation(m["name"])
        for c in m.get("columns", []):
            for t in c.get("data_tests", []):
                nom_t, args = (t, {}) if isinstance(t, str) else next(iter(t.items()))
                args = args or {}
                conf = args.get("config", {})
                a = args.get("arguments", args)
                where = f" and ({conf['where']})" if conf.get("where") else ""
                col = c["name"]
                if nom_t == "not_null":
                    sql = f"select 1 from {rel} where {col} is null{where}"
                elif nom_t == "unique":
                    sql = f"select {col} from {rel} where {col} is not null{where} group by 1 having count(*) > 1"
                elif nom_t == "accepted_values":
                    vals = ", ".join(f"'{v}'" for v in a["values"])
                    sql = f"select 1 from {rel} where {col} not in ({vals}){where}"
                elif nom_t == "relationships":
                    cible = rendre("{{ " + a["to"] + " }}")[0]
                    sql = (f"select 1 from {rel} s where s.{col} is not null{where} and not exists "
                           f"(select 1 from {cible} c where c.{a['field']} = s.{col})")
                else:
                    continue
                verdict(f"{m['name']}.{col} {nom_t}", sql, conf.get("severity", "error"))

if os.path.isdir(f"{DBT}/tests"):
    for f in sorted(os.listdir(f"{DBT}/tests")):
        if f.endswith(".sql"):
            sql_t, cap = rendre(open(f"{DBT}/tests/{f}").read())
            verdict(f"test {f[:-4]}", sql_t, cap.get("severity", "error"))

print(f"tests : {echecs} échec(s), {alertes} alerte(s)")
sys.exit(1 if echecs else 0)
