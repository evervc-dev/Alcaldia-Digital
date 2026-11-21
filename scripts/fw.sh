#!/bin/bash
# Ejecuta comandos en un OPNsense por SSH (clave de administración) desde el PC de administración del sitio.
# Uso: fw.sh <fw-a1|fw-a2|fw-b|IP> '<comandos sh>'      (el comando se pasa por stdin a "sh -s": evita csh)
set -euo pipefail
PROJ=${PROJ:-ACC-Lab}
PID=$(grep -l "\"name\": \"$PROJ\"" ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
case "$1" in
  fw-a1) IP=10.10.40.2; J=adm-pc ;;   fw-a2) IP=10.10.40.3; J=adm-pc ;;
  fw-a)  IP=10.10.40.1; J=adm-pc ;;   fw-b)  IP=10.20.40.1; J=adm-pc-b ;;
  *)     IP=$1; J=${JUMP:-adm-pc} ;;
esac
printf '%s\n' "$2" | docker exec -i "GNS3.$J.$PID" ssh -F /data/ssh/config -o ConnectTimeout=5 -o LogLevel=ERROR "root@$IP" sh -s
