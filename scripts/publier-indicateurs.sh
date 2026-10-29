#!/usr/bin/env bash
# Publie les indicateurs calculés par dbt : contrat bi du tableau de bord (mosip-bi-reporting : référentiel,
# pré-inscriptions, enrôlement), puis ref et ind.
# Tout est remplacé dans une seule transaction : l'API lit l'ancienne version jusqu'au COMMIT,
# sans jamais voir une table vide ni être bloquée.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . compose/.env; set +a
export PGCLIENTENCODING=UTF8
export PGPASSWORD="$PUBLISHER_PASSWORD"

# Clé du suivi d'un dossier (empreinte HMAC du RID) : passée à psql par une variable, jamais affichée. Sans clé, le
# suivi n'est pas publié ; le reste l'est.
CLE=()
[ -n "${SUIVI_HMAC_CLE:-}" ] && CLE=(-v "cle_suivi=$SUIVI_HMAC_CLE")

psql -h "$TRAITEMENT_PG_HOST" -U publisher -d mosip_bi -v ON_ERROR_STOP=1 -q "${CLE[@]}" <<'SQL'
BEGIN;
-- Référentiel : bi.zone, niveau par niveau (le parent est déjà en place)
\set n region
\i sql/publication/zone_niveau.sql
\set n prefecture
\i sql/publication/zone_niveau.sql
\set n commune
\i sql/publication/zone_niveau.sql
\set n canton
\i sql/publication/zone_niveau.sql
\set n localite
\i sql/publication/zone_niveau.sql
\set n centre
\i sql/publication/zone_niveau.sql
-- Contrat du backend (tables créées par Flyway, propriétaire bi_owner)
DELETE FROM bi.fait_preinscription_jour;
INSERT INTO bi.fait_preinscription_jour (jour, statut, sexe, demandes, consommees)
SELECT jour, statut, sexe, demandes, consommees FROM dm_preinscription.fait_preinscription_jour;
DELETE FROM bi.fait_preinscription_profil_jour;
INSERT INTO bi.fait_preinscription_profil_jour (jour, sexe, tranche_age, nationalite, demandes)
SELECT jour, sexe, tranche_age, nationalite, demandes FROM dm_preinscription.fait_preinscription_profil_jour;
DELETE FROM bi.fait_preinscription_zone_jour;
INSERT INTO bi.fait_preinscription_zone_jour (jour, zone_id, demandes)
SELECT f.jour, z.id, f.demandes
FROM dm_preinscription.fait_preinscription_zone_jour f
JOIN bi.zone z ON z.code = f.zone_code;
INSERT INTO bi.source_fraicheur (source, libelle, ordre, premiere_donnee, derniere_donnee, dernier_chargement)
SELECT 'preinscription', 'Pré-inscription', 6, premiere_donnee, derniere_donnee, now()
FROM dm_preinscription.fraicheur_preinscription
ON CONFLICT (source) DO UPDATE
   SET premiere_donnee    = excluded.premiere_donnee,
       derniere_donnee    = excluded.derniere_donnee,
       dernier_chargement = excluded.dernier_chargement;
-- Enrôlement (tables des migrations V1 à V3 du backend). Un code centre absent de bi.zone va sous « Centre non
-- référencé » (zone créée par V2) ; plusieurs codes inconnus s'y additionnent, d'où le regroupement.
DELETE FROM bi.fait_enrolement_jour;
INSERT INTO bi.fait_enrolement_jour (jour, centre_id, sexe, tranche_age, type_demande, inscriptions, niu_generes,
                                     en_cours, echouees, rejetees, non_classees)
SELECT f.jour, coalesce(z.id, h.id), f.sexe, f.tranche_age, f.type_demande,
       sum(f.inscriptions), sum(f.niu_generes), sum(f.en_cours), sum(f.echouees), sum(f.rejetees),
       sum(f.non_classees)
FROM dm_enrolement.fait_enrolement_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5;
DELETE FROM bi.fait_niu_jour;
INSERT INTO bi.fait_niu_jour (jour, centre_id, type_demande, niu_generes)
SELECT f.jour, coalesce(z.id, h.id), f.type_demande, sum(f.niu_generes)
FROM dm_enrolement.fait_niu_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3;
-- Profil des NIU (lot 6, ID Repository) : région du centre résolue en bi.zone (« Hors référentiel » sinon), puis
-- regroupé par sexe et âge d'une part, par nationalité d'autre part. Même total que bi.fait_niu_jour.
DELETE FROM bi.fait_niu_profil_jour;
INSERT INTO bi.fait_niu_profil_jour (jour, zone_id, sexe, tranche_age, niu_generes)
SELECT f.jour, coalesce(z.id, h.id), f.sexe, f.tranche_age, sum(f.niu_generes)
FROM dm_enrolement.fait_niu_profil_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'HORS_REFERENTIEL') h
LEFT JOIN bi.zone z ON z.code = f.code_region AND z.niveau = 'region'
GROUP BY 1, 2, 3, 4;
DELETE FROM bi.fait_niu_nationalite_jour;
INSERT INTO bi.fait_niu_nationalite_jour (jour, zone_id, nationalite, niu_generes)
SELECT f.jour, coalesce(z.id, h.id), f.nationalite, sum(f.niu_generes)
FROM dm_enrolement.fait_niu_profil_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'HORS_REFERENTIEL') h
LEFT JOIN bi.zone z ON z.code = f.code_region AND z.niveau = 'region'
GROUP BY 1, 2, 3;
INSERT INTO bi.source_fraicheur (source, libelle, ordre, premiere_donnee, derniere_donnee, dernier_chargement)
SELECT 'enrolement', 'Enrôlement', 1, premiere_donnee, derniere_donnee, now()
FROM dm_enrolement.fraicheur_enrolement
WHERE derniere_donnee IS NOT NULL
ON CONFLICT (source) DO UPDATE
   SET premiere_donnee    = excluded.premiere_donnee,
       derniere_donnee    = excluded.derniere_donnee,
       dernier_chargement = excluded.dernier_chargement;
-- Enrôlement v3 (migration V7 du backend) : étapes d'arrêt, stocks, délais. Même résolution des centres.
DELETE FROM bi.fait_arret_etape_jour;
INSERT INTO bi.fait_arret_etape_jour (jour, centre_id, type_demande, devenir, etape, etape_libelle, etape_ordre,
                                      inscriptions)
SELECT f.jour, coalesce(z.id, h.id), f.type_demande, f.devenir, f.etape, f.etape_libelle, f.etape_ordre,
       sum(f.inscriptions)
FROM dm_enrolement.fait_arret_etape_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5, 6, 7;
DELETE FROM bi.stock_en_cours;
INSERT INTO bi.stock_en_cours (centre_id, type_demande, etape, etape_libelle, etape_ordre, anciennete, inscriptions,
                               calcule_le)
SELECT coalesce(z.id, h.id), f.type_demande, f.etape, f.etape_libelle, f.etape_ordre, f.anciennete,
       sum(f.inscriptions), max(f.calcule_le)
FROM dm_enrolement.stock_en_cours f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5, 6;
-- Motifs (migration V9 du backend, décision du 26/10/2026) : étape (reg_stage_name) et motif (status_comment rangé
-- par seeds/ref_regprc_motifs.csv), jamais le texte de MOSIP. Même résolution des centres.
DELETE FROM bi.fait_arret_motif_jour;
INSERT INTO bi.fait_arret_motif_jour (jour, centre_id, type_demande, devenir, stage, stage_libelle, stage_ordre, motif,
                                      motif_libelle, motif_commentaire, motif_piste, inscriptions)
SELECT f.jour, coalesce(z.id, h.id), f.type_demande, f.devenir, f.stage, f.stage_libelle, f.stage_ordre, f.motif,
       f.motif_libelle, f.motif_commentaire, f.motif_piste, sum(f.inscriptions)
FROM dm_enrolement.fait_arret_motif_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11;
DELETE FROM bi.stock_en_cours_motif;
INSERT INTO bi.stock_en_cours_motif (centre_id, type_demande, stage, stage_libelle, stage_ordre, motif, motif_libelle,
                                     motif_commentaire, motif_piste, anciennete, inscriptions, calcule_le)
SELECT coalesce(z.id, h.id), f.type_demande, f.stage, f.stage_libelle, f.stage_ordre, f.motif, f.motif_libelle,
       f.motif_commentaire, f.motif_piste, f.anciennete, sum(f.inscriptions), max(f.calcule_le)
FROM dm_enrolement.stock_en_cours_motif f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
DELETE FROM bi.fait_delai_jour;
INSERT INTO bi.fait_delai_jour (jour, centre_id, type_demande, mesure, classe_h, paquets)
SELECT f.jour, coalesce(z.id, h.id), f.type_demande, f.mesure, f.classe_h, sum(f.paquets)
FROM dm_enrolement.fait_delai_jour f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2, 3, 4, 5;
DELETE FROM bi.stock_synchro_non_recue;
INSERT INTO bi.stock_synchro_non_recue (centre_id, anciennete, paquets, plus_ancienne_le, calcule_le)
SELECT coalesce(z.id, h.id), f.anciennete, sum(f.paquets), min(f.plus_ancienne_le), max(f.calcule_le)
FROM dm_enrolement.stock_synchro_non_recue f
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = f.code_centre AND z.niveau = 'centre'
GROUP BY 1, 2;
-- Catalogue des motifs (V11) : libellés lus par l'API du suivi d'un dossier, remplacés à chaque passage.
DELETE FROM bi.ref_motif;
INSERT INTO bi.ref_motif (motif, libelle, commentaire, piste)
SELECT motif, libelle, commentaire, piste FROM dm_enrolement.ref_motif;
-- Suivi d'un dossier : seulement les lignes écrites par dbt depuis la dernière publication (maj_le), en upsert sur
-- l'empreinte du RID. Au-delà de 200 000 lignes (premier chargement, dbt --full-refresh), rien n'est fait ici :
-- scripts/charger-suivi.sh charge par lots, hors de cette transaction.
\if :{?cle_suivi}
SELECT count(*) > 200000 AS suivi_trop_gros
FROM dm_enrolement.suivi_dossier
WHERE maj_le > (SELECT coalesce(max(maj_le), '-infinity') FROM bi.suivi_dossier) \gset
\if :suivi_trop_gros
\echo 'suivi d''un dossier non publié : plus de 200 000 lignes à écrire, lancer scripts/charger-suivi.sh'
\else
INSERT INTO bi.suivi_dossier (empreinte, centre_id, type_demande, enrole_le, synchronise_le, refus_poste, recu_le,
                              niu_le, devenir, etape, etape_libelle, etape_statut, derniere_transaction_le, motif,
                              maj_le)
SELECT hmac(s.rid, :'cle_suivi', 'sha256'), coalesce(z.id, h.id), s.type_demande, s.enrole_le, s.synchronise_le,
       s.refus_poste, s.recu_le, s.niu_le, s.devenir, s.etape, s.etape_libelle, s.etape_statut,
       s.derniere_transaction_le, s.motif, s.maj_le
FROM dm_enrolement.suivi_dossier s
CROSS JOIN (SELECT id FROM bi.zone WHERE code = 'CENTRE_NON_REFERENCE') h
LEFT JOIN bi.zone z ON z.code = s.code_centre AND z.niveau = 'centre'
WHERE s.maj_le > (SELECT coalesce(max(maj_le), '-infinity') FROM bi.suivi_dossier)
ON CONFLICT (empreinte) DO UPDATE
   SET centre_id = excluded.centre_id, type_demande = excluded.type_demande, enrole_le = excluded.enrole_le,
       synchronise_le = excluded.synchronise_le, refus_poste = excluded.refus_poste, recu_le = excluded.recu_le,
       niu_le = excluded.niu_le, devenir = excluded.devenir, etape = excluded.etape,
       etape_libelle = excluded.etape_libelle, etape_statut = excluded.etape_statut,
       derniere_transaction_le = excluded.derniere_transaction_le, motif = excluded.motif, maj_le = excluded.maj_le;
\endif
\else
\echo 'suivi d''un dossier non publié : SUIVI_HMAC_CLE absente de compose/.env'
\endif
-- Schémas ref et ind (première version, plus lus par le tableau de bord)
DELETE FROM ref.dim_date;
INSERT INTO ref.dim_date SELECT * FROM dwh.dim_date;
DELETE FROM ref.dim_statut;
INSERT INTO ref.dim_statut (status_code, libelle, ordre, est_final)
SELECT status_code, libelle, ordre, est_final FROM dwh.dim_statut;
DELETE FROM ind.ind_preinscription_jour;
INSERT INTO ind.ind_preinscription_jour SELECT * FROM dm_preinscription.ind_preinscription_jour;
COMMIT;
SQL
echo "$(date '+%F %T') publication terminée"
