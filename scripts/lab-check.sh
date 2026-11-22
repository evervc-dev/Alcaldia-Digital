#!/bin/bash
# Chequeo de salud del laboratorio (ejecutar tras abrir el proyecto y arrancar los nodos). Solo lectura.
cd "$(dirname "$0")/.."; P=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
ok() { printf "  \e[32m✔\e[0m %s\n" "$1"; }; ko() { printf "  \e[31m✘\e[0m %s\n" "$1"; FAIL=$((FAIL+1)); }; FAIL=0
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
fw() { bash scripts/fw.sh "$@" 2>/dev/null | grep -v SO_RCVBUF; }
echo "== Host"
chk "virbr0 (NAT libvirt) arriba" "ip -4 addr show virbr0 | grep -q 192.168.122.1"
chk "módulos bonding/openvswitch/8021q" "lsmod | grep -q '^bonding' && lsmod | grep -q '^openvswitch' && lsmod | grep -q '^8021q'"
echo "== Contenedores GNS3"
N=$(docker ps --format '{{.Names}}' | grep -c "\.$P$"); [ "$N" -ge 42 ] && ok "$N contenedores en marcha (4 de B en espera, detenidos a propósito)" || ko "solo $N contenedores en marcha (esperado ≥42)"
echo "== Red / WAN"
chk "Internet desde Site A (adm-pc → 1.1.1.1)" "docker exec GNS3.adm-pc.$P ping -c2 -W2 1.1.1.1"
chk "Internet desde Site B (adm-pc-b → 1.1.1.1)" "docker exec GNS3.adm-pc-b.$P ping -c2 -W2 1.1.1.1"
G=$(fw fw-a1 'pluginctl -r return_gateways_status | grep -c "\"status\": \"none\""'); [ "$G" = 2 ] && ok "fw-a1: WAN1 y WAN2 en línea" || ko "fw-a1: gateways en línea = $G/2"
C=$(fw fw-a1 'ifconfig | grep -c "carp: MASTER"'); [ "$C" = 8 ] && ok "fw-a1 MASTER de las 8 VIP" || ko "fw-a1 MASTER de $C/8 VIP (revisar: sysctl net.inet.carp.demotion)"
O=$(fw fw-b 'vtysh -c "show ip ospf neighbor" | grep -c Full'); [ "$O" -ge 2 ] && ok "OSPF A↔B Full en $O túneles" || ko "OSPF A↔B Full en $O/2 túneles"
chk "Site B → Site A (adm-pc-b → adm-pc)" "docker exec GNS3.adm-pc-b.$P ping -c2 -W2 10.10.40.50"
echo "== Servicios"
chk "AD: réplica dc1↔dc2 [ALL GOOD]" "docker exec GNS3.dc2.$P samba-tool drs showrepl --summary | grep -q 'ALL GOOD'"
chk "Portal público https://portal.evervc.dev (200)" "[ \$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://portal.evervc.dev/) = 200 ]"
chk "Áreas protegidas redirigen a Authelia (302)" "[ \$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://archivo.evervc.dev/) = 302 ]"
chk "Authelia arrancada" "docker exec GNS3.authelia.$P grep -q 'Startup complete' /config/authelia.log"
chk "ts1: xrdp escuchando :3389" "docker exec GNS3.cloudflared-a.$P nc -z -w3 10.10.20.40 3389"
chk "NAS A/B vivos" "docker exec GNS3.nas-a.$P curl -sf http://127.0.0.1:9000/minio/health/live && docker exec GNS3.nas-a.$P curl -sf http://10.20.60.10:9000/minio/health/live"
chk "Réplica del portal en B (< 2 h)" "docker exec GNS3.portal-db-b.$P sh -c 'f=/var/lib/postgresql/data/pgdata/replica_ok; [ \$(( \$(date +%s) - \$(date -d \$(cat \$f) +%s 2>/dev/null || stat -c %Y \$f) )) -lt 7200 ]'"
echo "== Sedes"
for n in 01 02 03; do
  T=$(docker exec GNS3.kit-sede-$n.$P sh -c 'swanctl --list-sas 2>/dev/null | grep -c ESTABLISHED' 2>/dev/null); O=$(docker exec GNS3.kit-sede-$n.$P sh -c 'vtysh -c "show ip ospf neighbor" | grep -c Full' 2>/dev/null)
  [ "$T" = 3 ] && [ "$O" = 3 ] && ok "kit-sede-$n: 3 túneles y 3 OSPF Full" || ko "kit-sede-$n: túneles=$T OSPF=$O (esperado 3/3)"
done
echo; [ $FAIL = 0 ] && echo "RESULTADO: todo OK" || echo "RESULTADO: $FAIL comprobación(es) fallida(s) — ver ESTADO.md (gotchas)"
