#!/usr/bin/env bash
# Chaîne analytique : dbt construit et teste le data warehouse et le data mart, puis on publie.
# Si dbt échoue (erreur ou test en échec), rien n'est publié : l'API garde les chiffres précédents.
set -euo pipefail
cd "$(dirname "$0")/../compose"

# Un seul passage à la fois (cron toutes les 5 minutes ou lancement à la main) : deux passages simultanés
# inséreraient les mêmes événements. Depuis cron, un passage déjà en cours fait sauter celui-ci ; à la main, on attend.
exec 9>/tmp/mosip-analytique.lock
if ! flock -n 9; then
  [ -t 0 ] || exit 0
  echo "Un passage est en cours, attente de sa fin…"
  flock 9
fi
echo "$(date '+%F %T') début"
docker compose run --rm -T dbt build
../scripts/publier-indicateurs.sh
