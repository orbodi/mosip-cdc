#!/usr/bin/env bash
# Routage des réponses aux connexions reçues sur ens34 (172.16.26.86, adresse du tableau de bord pour les utilisateurs,
# 30/10/2026).
#
# Le serveur a deux interfaces : ens33 (172.16.44.186) et ens34 (172.16.26.86, route par défaut via 172.16.26.1).
# Un poste du réseau 172.16.44.0/24 qui ouvre http://172.16.26.86:5173 passe par le routeur ; sans ces règles, le
# serveur lui répond en direct par ens33, le pare-feu du routeur ne voit pas la réponse et coupe la connexion (constaté
# le 30/10/2026 par tcpdump : poignée de main réussie, puis plus rien). Ici, chaque connexion entrée par ens34 est
# marquée, et ses réponses, celles des conteneurs Docker comprises, repartent par ens34 via 172.16.26.1.
# Le reste du trafic (BD traitement, MOSIP, Kafka) n'est pas touché.
#
#   ops/reseau/routage-ens34.sh appliquer   # relançable : ne crée que ce qui manque
#   ops/reseau/routage-ens34.sh retirer     # revient à l'état d'avant
#   ops/reseau/routage-ens34.sh etat
#
# Au démarrage : service systemd ops/reseau/routage-ens34.service (voir son en-tête).
set -euo pipefail

INTERFACE=ens34
ADRESSE=172.16.26.86
RESEAU=172.16.26.0/24
PASSERELLE=172.16.26.1
TABLE=126
MARQUE=0x26

REGLES=(
  "PREROUTING -i $INTERFACE -m conntrack --ctstate NEW -j CONNMARK --set-mark $MARQUE"
  "PREROUTING ! -i $INTERFACE -m connmark --mark $MARQUE -j CONNMARK --restore-mark"
  "OUTPUT -m connmark --mark $MARQUE -j CONNMARK --restore-mark"
)

appliquer() {
  ip route replace default via "$PASSERELLE" dev "$INTERFACE" table "$TABLE"
  ip route replace "$RESEAU" dev "$INTERFACE" src "$ADRESSE" table "$TABLE"
  for r in "${REGLES[@]}"; do
    # shellcheck disable=SC2086
    iptables -t mangle -C $r 2>/dev/null || iptables -t mangle -A $r
  done
  ip rule show | grep -q "fwmark $MARQUE lookup $TABLE" || ip rule add fwmark "$MARQUE" table "$TABLE" priority 1000
  echo "routage $INTERFACE appliqué"
}

retirer() {
  while ip rule show | grep -q "fwmark $MARQUE lookup $TABLE"; do
    ip rule del fwmark "$MARQUE" table "$TABLE" priority 1000
  done
  for r in "${REGLES[@]}"; do
    # shellcheck disable=SC2086
    while iptables -t mangle -C $r 2>/dev/null; do iptables -t mangle -D $r; done
  done
  ip route flush table "$TABLE" 2>/dev/null || true
  echo "routage $INTERFACE retiré"
}

etat() {
  echo "--- table $TABLE"; ip route show table "$TABLE"
  echo "--- règle";      ip rule show | grep "fwmark $MARQUE" || echo "(aucune)"
  echo "--- mangle";     iptables -t mangle -S | grep -E "$MARQUE" || echo "(aucune)"
}

case "${1:-}" in
  appliquer) appliquer ;;
  retirer)   retirer ;;
  etat)      etat ;;
  *) echo "usage : $0 appliquer|retirer|etat" >&2; exit 2 ;;
esac
