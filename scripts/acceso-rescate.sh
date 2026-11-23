#!/bin/bash
# RESCATE (AD caído o página inaccesible): deja pasar a <usuario> por gate durante <horas> (máx. 8) con un archivo LOCAL.
# No sustituye el login: si el AD está del todo caído, Authelia no autentica; quedan las cuentas locales (SSH de firewalls, Zabbix Admin, GLPI glpi).
# Uso: acceso-rescate.sh <usuario> <horas> "<motivo>"   |   acceso-rescate.sh quitar
set -euo pipefail; PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename); L=~/.local/state/acc/rescate.log
if [ "${1:-}" = quitar ]; then docker exec "GNS3.gate.$PID" sh -c ': > /etc/acc/rescate.json'; echo "$(date -Is) $USER quitó el rescate" | tee -a "$L"; exit; fi
U=${1:?usuario}; H=${2:?horas}; M=${3:?motivo}; [[ $U =~ ^[a-z0-9._-]+$ && $H =~ ^[1-8]$ ]] || { echo "usuario u horas (1-8) no válidos"; exit 1; }
printf '{"usuarios":["%s"],"hasta":%s}' "$U" $(( $(date +%s) + H * 3600 )) | docker exec -i "GNS3.gate.$PID" sh -c 'umask 077; cat > /etc/acc/rescate.json'
echo "$(date -Is) $USER dio rescate a $U $H h: $M" | tee -a "$L"
