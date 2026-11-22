#!/bin/bash
# Procedimiento P-A (Fase 5): pérdida total del Site A -> servicios en el Site B (DR en caliente).
# ANTES (operador, GUI de GNS3 o agente con gns3-mcp): ENCENDER los nodos en espera del Site B:
#     portal-b, authelia-b, gate-b, archivo-b
# Este script hace el resto y mide los tiempos:
#   1) portal-db-b deja de ser réplica (si no, al volver A la copia horaria pisaría los trámites nuevos)
#   2) configuración de los servicios de B desde .env (services-setup.sh SITE=B)
#   3) archivo-b: restaura los documentos del último respaldo desde nas-b (restic)
#   4) DNS de Cloudflare -> túnel del Site B (portal, archivo, auth)
#   5) verificación desde Internet
# Uso: dr-activar-b.sh
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
C() { echo "GNS3.$1.$PID"; }
T0=$(date +%s); paso() { echo "[$(( $(date +%s) - T0 ))s] $*"; }

for n in portal-b authelia-b gate-b archivo-b portal-db-b nas-b cloudflared-b dc2; do
  docker inspect -f '{{.State.Running}}' "$(C $n)" 2>/dev/null | grep -q true || { echo "! $n no está encendido: enciéndalo primero"; exit 1; }
done

# 1) fin de la réplica: marca DR (la respetan las imágenes nuevas) y se detiene el bucle en marcha
docker exec "$(C portal-db-b)" sh -c 'touch /etc/acc/DR-ACTIVO
  for s in $(ps -o pid,args | awk "\$2==\"sleep\" && (\$3==3600 || \$3==300) {print \$1}"); do
    pp=$(awk "/^PPid/{print \$2}" /proc/$s/status); kill "$pp" "$s" 2>/dev/null; done; true'
paso "portal-db-b: réplica detenida, BD en modo primario (último dato: $(docker exec "$(C portal-db-b)" cat /var/lib/postgresql/data/pgdata/replica_ok))"

# 2) servicios de B
SITE=B bash scripts/services-setup.sh >/dev/null 2>&1 && paso "servicios del Site B configurados (portal-b, authelia-b, gate-b, cloudflared-b)"

# 3) archivo-b desde nas-b
docker exec -e RESTIC_PASSWORD="$RESTIC_PASSWORD" -e AWS_ACCESS_KEY_ID=restic -e AWS_SECRET_ACCESS_KEY="$RESTIC_S3_KEY" "$(C nas-b)" sh -c \
  'export RESTIC_REPOSITORY=s3:http://127.0.0.1:9000/respaldos/repo; mkdir -p /tmp/dr-archivo; restic restore latest --no-cache --no-lock --host archivo --target /tmp/dr-archivo -q --include /srv'
docker exec "$(C nas-b)" tar -C /tmp/dr-archivo/srv -cf - . | docker exec -i "$(C archivo-b)" tar -C /srv -xf -
docker exec "$(C archivo-b)" sh -c 'chown -R user /srv 2>/dev/null; true'
paso "archivo-b: $(docker exec "$(C archivo-b)" sh -c 'find /srv -type f ! -name ".*" | wc -l') documentos restaurados desde nas-b"

# 4) DNS -> Site B
bash scripts/dr-dns-switch.sh B | sed 's/^/    /'
paso "DNS de Cloudflare apuntando al Site B"

# 5) verificación
for i in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://portal.evervc.dev/)" = 200 ] && break; sleep 3; done
paso "portal.evervc.dev: HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://portal.evervc.dev/) — $(curl -s --max-time 8 https://portal.evervc.dev/ | grep -oE 'Site [AB]' | head -1)"
paso "archivo.evervc.dev (pide login): HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://archivo.evervc.dev/)"
paso "auth.evervc.dev: HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://auth.evervc.dev/)"
echo "Site B ACTIVO. Retorno: scripts/dr-retorno-a.sh (cuando el Site A vuelva)."
