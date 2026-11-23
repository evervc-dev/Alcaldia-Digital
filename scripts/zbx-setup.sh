#!/bin/bash
# F8: configura Zabbix por API (hosts, comprobaciones, disparadores, alertas, mapa). Idempotente.
# Se ejecuta en el contenedor 'portal' (Python 3, VLAN SERVIDORES); los secretos van por entorno desde .env.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
docker exec -i -e ZABBIX_ADMIN_PASS -e ZBX_SNMP_COMMUNITY -e PORTAL_DB_PASS -e GLPI_ZABBIX_PASS -e SVC_LDAP_PASS "GNS3.portal.$PID" python3 - < scripts/zbx-setup.py
