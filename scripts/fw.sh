#!/bin/bash
# Ejecuta comandos en un OPNsense por SSH (clave de administración) desde el PC de administración del sitio.
# Uso: fw.sh <fw-a1|fw-a2|fw-b|IP> '<comandos sh>'      (el comando se pasa por stdin a "sh -s": evita csh)
#      fw.sh <fw> -   < script.sh                       (script por la entrada estándar: para contenidos grandes)
set -euo pipefail
PROJ=${PROJ:-ACC-Lab}
PID=$(grep -l "\"name\": \"$PROJ\"" ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
case "$1" in
  fw-a1) IP=10.10.40.2; J=adm-pc ;;   fw-a2) IP=10.10.40.3; J=adm-pc ;;
  fw-a)  IP=10.10.40.1; J=adm-pc ;;   fw-b)  IP=10.20.40.1; J=adm-pc-b ;;
  *)     IP=$1; J=${JUMP:-adm-pc} ;;
esac
# GESTION=1: acceso fuera de banda por la VLAN GESTION (si las reglas del FW están rotas, la anti-bloqueo de OPNsense
# sigue aceptando SSH en LAN=GESTION). Salto: nc en el switch del sitio (su interfaz mgmt está en GESTION).
if [ "${GESTION:-0}" = 1 ]; then
  case "$1" in fw-a1) GIP=10.10.10.2; SW=sw-a1 ;; fw-a2) GIP=10.10.10.3; SW=sw-a2 ;; fw-b) GIP=10.20.10.1; SW=sw-b1 ;; *) echo "GESTION=1: solo fw-a1/fw-a2/fw-b"; exit 1 ;; esac
  K=$(mktemp); trap 'rm -f -- "$K"' EXIT; docker exec "GNS3.$J.$PID" cat /data/ssh/id_ed25519 > "$K"; chmod 600 "$K"
  { if [ "$2" = - ]; then cat; else printf '%s\n' "$2"; fi; } | ssh -i "$K" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=8 -o ProxyCommand="docker exec -i GNS3.$SW.$PID nc %h %p" "root@$GIP" sh -s
  exit $?
fi
{ if [ "$2" = - ]; then cat; else printf '%s\n' "$2"; fi; } | docker exec -i "GNS3.$J.$PID" ssh -F /data/ssh/config -o ConnectTimeout=5 -o LogLevel=ERROR "root@$IP" sh -s
