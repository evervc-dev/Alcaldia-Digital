#!/bin/bash
# Restaura la configuración de un equipo de red desde la copia COMPLETA del NAS (respaldos/configuraciones, WORM),
# como pide RQ-11 (Fase 2: «restauración de una configuración») y la Fase 5 (configuración de red en los NAS).
#   OPNsense (fw-a1, fw-a2, fw-b): /conf/config.xml + recarga de filtro, IPsec, OSPF e IDS; si SSH por ADMIN no
#   responde (reglas rotas), entra fuera de banda por la VLAN GESTION (fw.sh con GESTION=1)
#   FRR (isp1, isp2, inet-core, kit-sede-NN): frr.conf + reinicio de FRR
#   (los switches OVS se reconstruyen con deploy-config.sh: su respaldo es el volcado de ovs-vsctl, solo para comparar)
# Uso: restaurar-config.sh <equipo> [AAAA-MM-DD_HHMM]   (sin fecha: la copia más reciente)
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
EQ=${1:?equipo}; PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
NAS="GNS3.nas-a.$PID"; T0=$(date +%s)
docker exec -e RP="$MINIO_ROOT_PASS" "$NAS" sh -c 'mc alias set a http://127.0.0.1:9000 admin-nas "$RP" >/dev/null'
COPIA=${2:+$2.tar.gz}; COPIA=${COPIA:-$(docker exec "$NAS" mc ls a/respaldos/configuraciones/ | awk '{print $NF}' | sort | tail -1)}
case "$EQ" in fw-*) F="$EQ.config.xml" ;; isp*|inet-core|kit-sede-*) F="$EQ.frr.conf" ;; *) echo "equipo no restaurable con este script: $EQ"; exit 1 ;; esac
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT
docker exec "$NAS" mc cat "a/respaldos/configuraciones/$COPIA" | tar -xzf - -C "$TMP" "./$F"
echo "copia: respaldos/configuraciones/$COPIA (nas-a, WORM) -> $F ($(wc -c < "$TMP/$F") bytes, sha256 $(sha256sum "$TMP/$F" | cut -c1-12))"
case "$EQ" in
  fw-*)
    { echo "b64decode -r > /tmp/restaurar.xml <<'FIN_B64'"; base64 -w76 "$TMP/$F"; echo "FIN_B64"
      cat <<'FIN'
xmllint --noout /tmp/restaurar.xml || { echo "XML inválido: no se restaura"; exit 1; }
cp /conf/config.xml "/conf/backup/config-antes-de-restaurar-$(date +%s).xml"
mv /tmp/restaurar.xml /conf/config.xml; rm -f /tmp/config.cache
configctl filter reload >/dev/null; pluginctl -s strongswan restart >/dev/null 2>&1; configctl quagga restart >/dev/null 2>&1
configctl ids restart >/dev/null 2>&1   # (rc.reload_all tarda minutos: se recargan solo filtro, IPsec, OSPF e IDS)
echo "$(hostname -s): config.xml restaurado y servicios recargados"
FIN
    } > "$TMP/script.sh"
    # 1.º por ADMIN; si no responde (p. ej. las reglas del FW están rotas), fuera de banda por GESTION
    if bash scripts/fw.sh "$EQ" 'true' >/dev/null 2>&1; then bash scripts/fw.sh "$EQ" - < "$TMP/script.sh" 2>&1 | grep -v SO_RCVBUF
    else echo "SSH por ADMIN no responde: acceso fuera de banda por la VLAN GESTION"; GESTION=1 bash scripts/fw.sh "$EQ" - < "$TMP/script.sh" 2>&1 | grep -v SO_RCVBUF; fi ;;
  *)
    docker exec -i "GNS3.$EQ.$PID" sh -c 'cat > /etc/frr/frr.conf && chown frr:frr /etc/frr/frr.conf 2>/dev/null; (rc-service frr restart || /usr/lib/frr/frrinit.sh restart) >/dev/null 2>&1; echo "frr.conf restaurado y FRR reiniciado"' < "$TMP/$F" ;;
esac
echo "restauración aplicada en $(( $(date +%s) - T0 )) s"
