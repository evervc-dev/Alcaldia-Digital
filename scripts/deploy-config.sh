#!/bin/bash
# Copia la configuración versionada (config/nodes/<nodo>/) a las rutas PERSISTENTES del contenedor GNS3.
# Mapeo:  interfaces -> /etc/network/interfaces   frr.conf -> /etc/frr/frr.conf
#         *.nft -> /etc/nftables.d/               swanctl.conf -> /etc/swanctl/conf.d/
#         dnsmasq.conf -> /etc/dnsmasq.d/         snmpd.conf -> /etc/snmp/snmpd.conf
#         ovs.sh -> /etc/openvswitch/acc-ovs.sh (y se ejecuta: queda en conf.db)
#         files/<ruta> -> /<ruta> (cualquier otro archivo, ruta absoluta)
# Uso: deploy-config.sh <proyecto> <nodo...>     (luego reiniciar el nodo con gns3-mcp)
set -euo pipefail
cd "$(dirname "$0")/.."
PROJ_NAME=$1; shift
PID=$(grep -l "\"name\": \"$PROJ_NAME\"" ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
[ -n "$PID" ] || { echo "proyecto $PROJ_NAME no encontrado"; exit 1; }
for n in "$@"; do
  C="GNS3.$n.$PID"; D=config/nodes/$n
  docker inspect "$C" >/dev/null 2>&1 || { echo "! $n: contenedor no está en marcha"; continue; }
  [ -d "$D" ] || { echo "! $n: no existe $D"; continue; }
  # OJO: no usar "docker cp": GNS3 monta los volúmenes con bind DENTRO del contenedor y docker cp
  # escribe en la capa inferior (se pierde al reiniciar). Escribir desde dentro con docker exec.
  cp_in() { docker exec -i "$C" sh -c "mkdir -p '$(dirname "$2")' && cat > '$2'" < "$1"; echo "  $n: $2"; }
  for f in "$D"/*; do
    b=$(basename "$f")
    case "$b" in
      interfaces)   cp_in "$f" /etc/network/interfaces ;;
      frr.conf)     cp_in "$f" /etc/frr/frr.conf; docker exec "$C" chown frr:frr /etc/frr/frr.conf 2>/dev/null || true ;;
      *.nft)        cp_in "$f" "/etc/nftables.d/$b" ;;
      swanctl.conf) cp_in "$f" /etc/swanctl/conf.d/acc.conf ;;
      dnsmasq.conf) cp_in "$f" /etc/dnsmasq.d/acc.conf ;;
      snmpd.conf)   cp_in "$f" /etc/snmp/snmpd.conf ;;
      ovs.sh)       cp_in "$f" /etc/openvswitch/acc-ovs.sh; docker exec "$C" sh /etc/openvswitch/acc-ovs.sh && echo "  $n: ovs.sh ejecutado (conf.db)" ;;
      files)        (cd "$f" && find . -type f) | while read -r r; do cp_in "$f/$r" "/${r#./}"; done ;;
    esac
  done
done
