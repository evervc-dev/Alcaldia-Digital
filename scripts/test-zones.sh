#!/bin/bash
# T1 (F10): matriz de conectividad entre zonas (RQ-09). Cada fila: origen destino puerto esperado descripción.
# Comprueba con nc (TCP) desde el nodo origen; un rechazo inmediato (puerto cerrado) cuenta como alcanzable. Esperado: P = debe pasar, B = debe bloquearse.
# Uso: test-zones.sh [-v]     Salida: tabla + resumen; código 0 si todo coincide con la política.
set -uo pipefail; cd "$(dirname "$0")/.."
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
MATRIZ='
# --- Internet (atacante-ext, 198.18.0.66): ningún puerto abierto, todo entra por Cloudflare Tunnel
atacante-ext 203.0.113.4   22   B Internet -> VIP WAN1 Site A: SSH
atacante-ext 203.0.113.4   80   B Internet -> VIP WAN1 Site A: HTTP
atacante-ext 203.0.113.4   443  B Internet -> VIP WAN1 Site A: HTTPS/GUI
atacante-ext 198.51.100.4  443  B Internet -> VIP WAN2 Site A: HTTPS/GUI
atacante-ext 203.0.113.10  22   B Internet -> WAN Site B: SSH
atacante-ext 203.0.113.251 22   B Internet -> IP pública de la sede 1 (CGNAT)
# --- DMZ (nginx-dmz): solo los servicios publicados
nginx-dmz    10.10.20.20   8000 P DMZ -> portal
nginx-dmz    10.10.20.21   80   P DMZ -> archivo
nginx-dmz    10.10.20.11   9091 P DMZ -> authelia
nginx-dmz    10.10.20.10   53   P DMZ -> DNS dc1
nginx-dmz    10.10.20.10   389  B DMZ -> LDAP dc1
nginx-dmz    10.10.20.22   5432 B DMZ -> BD del portal
nginx-dmz    10.10.20.40   3389 B DMZ -> RDP ts1 (solo cloudflared-a/WARP)
nginx-dmz    10.10.60.10   9000 B DMZ -> NAS
nginx-dmz    10.10.40.50   22   B DMZ -> ADMIN
nginx-dmz    10.10.10.11   22   B DMZ -> GESTION
# --- Sede (pc-01-a): AD de cliente, DNS y escritorios; nada más (hub-and-spoke)
pc-01-a      10.10.20.10   53   P Sede -> DNS dc1
pc-01-a      10.10.20.10   389  P Sede -> LDAP dc1 (puestos unidos al dominio)
pc-01-a      10.20.20.10   88   P Sede -> Kerberos dc2
pc-01-a      10.10.20.40   3389 P Sede -> RDP ts1
pc-01-a      10.10.20.20   8000 B Sede -> portal interno (usa el público)
pc-01-a      10.10.20.22   5432 B Sede -> BD del portal
pc-01-a      10.10.60.10   9000 B Sede -> NAS
pc-01-a      10.10.10.11   22   B Sede -> GESTION
pc-01-a      10.10.40.50   22   B Sede -> ADMIN
pc-01-a      10.100.2.1    53   B Sede 1 -> Sede 2 (lateral)
pc-01-a      10.100.2.196  22   B Sede 1 -> PC de la sede 2 (lateral)
pc-01-a      10.10.20.2    22   B Sede -> SSH del propio firewall (T5)
pc-01-a      10.10.40.2    443  B Sede -> GUI del firewall en ADMIN (T5)
pc-01-a      10.10.20.1    53   B Sede -> DNS del firewall (usa dc1/dc2)
# --- USUARIOS (usr-pc): web/DNS, AD de cliente y escritorios
usr-pc       10.10.20.10   53   P USUARIOS -> DNS dc1
usr-pc       10.10.20.10   389  P USUARIOS -> LDAP dc1 (puestos)
usr-pc       10.10.20.40   3389 P USUARIOS -> RDP ts1
usr-pc       10.10.20.21   80   B USUARIOS -> archivo directo (solo por la URL pública con MFA)
usr-pc       10.10.20.20   8000 B USUARIOS -> portal directo
usr-pc       10.10.20.31   80   B USUARIOS -> GLPI directo
usr-pc       10.10.20.50   80   B USUARIOS -> LAM directo (solo WARP)
usr-pc       10.20.20.10   53   P USUARIOS -> DNS dc2
usr-pc       10.10.20.22   5432 B USUARIOS -> BD del portal
usr-pc       10.10.60.10   9000 B USUARIOS -> NAS
usr-pc       10.10.10.11   22   B USUARIOS -> GESTION
usr-pc       10.10.40.50   22   B USUARIOS -> ADMIN
usr-pc       1.1.1.1       443  P USUARIOS -> Internet
# --- ADMIN (adm-pc): personal del centro, acceso total
adm-pc       10.10.20.22   5432 P ADMIN -> BD del portal
adm-pc       10.10.60.10   9000 P ADMIN -> NAS
adm-pc       10.10.20.10   389  P ADMIN -> LDAP dc1
adm-pc       1.1.1.1       443  P ADMIN -> Internet
# --- GESTION (sw-a1): gestión y actualizaciones, nunca hacia ADMIN
sw-a1        10.10.40.50   22   B GESTION -> ADMIN
sw-a1        1.1.1.1       443  P GESTION -> Internet (actualizaciones)
# --- SERVIDORES (portal): réplicas, respaldos y actualizaciones; nada hacia DMZ/ADMIN
portal       10.10.60.10   9000 P SERVIDORES -> NAS (restic)
portal       10.20.20.22   5432 P SERVIDORES -> BD réplica Site B
portal       10.10.30.10   80   B SERVIDORES -> DMZ
portal       10.10.40.50   22   B SERVIDORES -> ADMIN
portal       10.10.60.10   9001 B SERVIDORES -> consola del NAS
portal       1.1.1.1       443  P SERVIDORES -> Internet (actualizaciones)
'
ok=0; mal=0; V=${1:-}
printf "%-4s %-10s %-48s %s\n" "" "esperado" "flujo" "resultado"
while read -r src dst port exp desc; do
  [ -z "${src:-}" ] || [ "${src:0:1}" = "#" ] && continue
  # Un puerto CERRADO responde al instante (RST: el firewall dejó pasar el paquete) -> cuenta como "pasa";
  # uno FILTRADO por el firewall agota la espera (3 s). (El nc de BusyBox no imprime "refused": se mide el tiempo.)
  t0=$(date +%s%N); docker exec "GNS3.$src.$PID" nc -z -w3 "$dst" "$port" >/dev/null 2>&1; rc=$?; ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  if [ $rc = 0 ] || [ $ms -lt 1500 ]; then r=P; else r=B; fi
  if [ "$r" = "$exp" ]; then ok=$((ok+1)); m="✔"; else mal=$((mal+1)); m="✘"; fi
  txt=$([ "$r" = P ] && echo "pasa" || echo "bloqueado")
  [ "$m" = "✘" ] || [ "$V" = -v ] && printf "%-4s %-10s %-48s %s\n" "$m" "$([ "$exp" = P ] && echo pasa || echo bloquear)" "$desc ($dst:$port)" "$txt"
done <<< "$MATRIZ"
echo "RESULTADO T1: $ok de $((ok+mal)) flujos según la política; $mal discrepancias"
# Suplantación: dentro de la VLAN SERVIDORES no hay firewall; las aplicaciones deben ignorar Remote-User si no viene de nginx-dmz
sup() { # puerto ip petición patrón-de-acceso descripción
  r=$(docker exec "GNS3.ts1.$PID" bash -c 'exec 3<>/dev/tcp/'"$1/$2"' && printf "'"$3"' HTTP/1.0\r\nHost: x\r\nRemote-User: ana.funcionaria\r\nContent-Length: 0\r\n\r\n" >&3 && timeout 6 cat <&3' 2>/dev/null)
  if [ -z "$r" ]; then echo "✘ $5: sin respuesta (no concluyente)"; mal=$((mal+1))
  elif grep -qE "$4" <<<"$r"; then echo "✘ $5: SUPLANTACIÓN POSIBLE"; mal=$((mal+1)); else echo "✔ $5: cabecera ignorada"; fi; }
sup 10.10.20.20 8000 "GET /funcionarios" "Sesión: <b>ana" "ts1 -> portal con Remote-User falso"
sup 10.10.20.21 80 "POST /api/login" "^HTTP/1.. 200" "ts1 -> archivo con Remote-User falso"
[ $mal = 0 ]
