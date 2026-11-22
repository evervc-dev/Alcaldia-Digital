#!/bin/bash
# Aplica la configuración versionada a un OPNsense (idempotente) y recarga servicios.
# Uso: opn-apply.sh fw-a1|fw-a2|fw-b [servicios...]   (por defecto: filter dnsmasq strongswan frr)
# Requiere el servidor HTTP del host:  (cd config/opnsense && python3 -m http.server 8088 --bind 192.168.122.1)
set -euo pipefail; cd "$(dirname "$0")/.."
FW=$1; shift; SVCS=${*:-filter dnsmasq strongswan frr}
case "$FW" in fw-a1) S=site-a.php; R=a1 ;; fw-a2) S=site-a.php; R=a2 ;; fw-b) S=site-b.php; R=b ;; *) echo "fw desconocido"; exit 1 ;; esac
set -a; . ./.env; set +a; printf '%s' "$IPSEC_PSK_AB" > config/opnsense/ipsec.psk   # el FW lo borra al leerlo
printf '%s' "$IPSEC_PSK_SEDES" > config/opnsense/ipsec-sedes.psk
curl -fsS -o /dev/null http://192.168.122.1:8088/ || { echo "servidor HTTP del host no responde en :8088"; exit 1; }
RELOAD=""
for s in $SVCS; do case $s in
  filter) RELOAD="$RELOAD configctl filter reload >/dev/null;" ;;
  dnsmasq) RELOAD="$RELOAD pluginctl -s dnsmasq restart >/dev/null;" ;;
  strongswan) RELOAD="$RELOAD pluginctl -s strongswan restart >/dev/null;" ;;
  frr) RELOAD="$RELOAD configctl quagga restart >/dev/null 2>&1;" ;;
  dpinger) RELOAD="$RELOAD pluginctl -s dpinger restart >/dev/null;" ;;
esac; done
bash scripts/fw.sh "$FW" "B=http://192.168.122.1:8088; for f in $S wan-ab.inc.php dhcp.inc.php ipsec.psk ipsec-sedes.psk; do fetch -qo /root/\$f \$B/\$f; done; cd /usr/local/opnsense/mvc && php /root/$S $R | grep -vE '^ok: [a-z-]+( \(|$)'; $RELOAD echo 'servicios recargados: $SVCS'" 2>&1 | grep -v SO_RCVBUF
