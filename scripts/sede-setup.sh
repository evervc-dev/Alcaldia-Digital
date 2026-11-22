#!/bin/bash
# Despliega una sede generada con new-sede.sh: configuración del kit y de sus PC + PSK (desde .env). Luego reiniciar nodos.
# Uso: sede-setup.sh <N> [N...]
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
for n in "$@"; do NN=$(printf %02d $((10#$n)))
  bash scripts/deploy-config.sh ACC-Lab kit-sede-$NN pc-$NN-a pc-$NN-b | grep -c ": /" | sed "s/^/sede $NN: archivos desplegados: /"
  printf 'secrets {\n    ike-sedes {\n        id-1 = kit-sede-%s.alcaldia.lab\n        secret = "%s"\n    }\n}\n' "$NN" "$IPSEC_PSK_SEDES" \
    | docker exec -i "GNS3.kit-sede-$NN.$PID" sh -c 'umask 077; cat > /etc/swanctl/acc-secrets.conf' && echo "sede $NN: PSK instalada"
  printf "rocommunity %s 10.10.20.30/32\n" "$ZBX_SNMP_COMMUNITY" | docker exec -i "GNS3.kit-sede-$NN.$PID" sh -c 'umask 077; cat > /etc/snmp/acc-community.conf; chmod +x /etc/snmp/acc-estado.sh; pkill snmpd; sleep 1; snmpd -Lsd' && echo "sede $NN: SNMP activo"
done
