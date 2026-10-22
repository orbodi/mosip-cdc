#!/usr/bin/env bash
# Chaîne analytique : dbt construit et teste le data warehouse et le data mart, puis on publie.
# Si dbt échoue (erreur ou test en échec), rien n'est publié : l'API garde les chiffres précédents.
set -euo pipefail
cd "$(dirname "$0")/../compose"
echo "$(date '+%F %T') début"
docker compose run --rm -T dbt build
../scripts/publier-indicateurs.sh
