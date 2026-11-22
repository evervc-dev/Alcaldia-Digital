#!/bin/bash
# Retorno al Site A tras un DR (P-A inverso). Requiere el Site A ya operativo (firewalls y cloudflared-a encendidos).
#   1) BD: lo registrado en B durante el DR (trámites) se lleva a portal-db (A)  [B -> A]
#   2) archivo: documentos de archivo-b -> archivo (A)
#   3) DNS de Cloudflare -> Site A
#   4) portal-db-b vuelve a ser réplica (quitar la marca DR; el agente/operador REINICIA el nodo portal-db-b)
# Después: APAGAR portal-b, authelia-b, gate-b y archivo-b (vuelven a espera).
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
C() { echo "GNS3.$1.$PID"; }
T0=$(date +%s); paso() { echo "[$(( $(date +%s) - T0 ))s] $*"; }
Q='select count(*) from tramites'

docker exec "$(C portal-db)" sh -c ". /etc/acc/pg.env; PGPASSWORD=\$POSTGRES_PASSWORD pg_isready -q -h 10.20.20.22" || { echo "! el Site A aún no alcanza al Site B"; exit 1; }

# 1) BD B -> A (pg_dump de la BD portal en B y restauración limpia en A)
docker exec "$(C portal-db)" sh -c '. /etc/acc/pg.env; export PGPASSWORD=$POSTGRES_PASSWORD
  pg_dump -h 10.20.20.22 -U $POSTGRES_USER -d portal -Fc -f /tmp/retorno.dump && pg_restore -h 127.0.0.1 -U $POSTGRES_USER -d portal --clean --if-exists /tmp/retorno.dump 2>/dev/null; true'
paso "BD: trámites en B=$(docker exec "$(C portal-db-b)" sh -c ". /etc/acc/pg.env; PGPASSWORD=\$POSTGRES_PASSWORD psql -tA -h 127.0.0.1 -U \$POSTGRES_USER -d portal -c '$Q'") -> A=$(docker exec "$(C portal-db)" sh -c ". /etc/acc/pg.env; PGPASSWORD=\$POSTGRES_PASSWORD psql -tA -h 127.0.0.1 -U \$POSTGRES_USER -d portal -c '$Q'")"

# 2) archivo B -> A
docker exec "$(C archivo-b)" tar -C /srv -cf - --exclude=.gns3_perms . | docker exec -i "$(C archivo)" tar -C /srv -xf -
docker exec "$(C archivo)" sh -c 'chown -R user /srv 2>/dev/null; true'
paso "archivo: $(docker exec "$(C archivo)" sh -c 'find /srv -type f ! -name ".*" | wc -l') documentos en A"

# 3) DNS -> A
bash scripts/dr-dns-switch.sh A | sed 's/^/    /'
for i in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://portal.evervc.dev/)" = 200 ] && break; sleep 3; done
paso "portal.evervc.dev: HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://portal.evervc.dev/) — $(curl -s --max-time 8 https://portal.evervc.dev/ | grep -oE 'Site [AB]' | head -1)"

# Cloudflare tarda 1-2 min en propagar el cambio a todos sus nodos: B debe seguir sirviendo mientras tanto
paso "esperando 120 s de propagación de DNS en Cloudflare antes de devolver B a espera..."; sleep 120
# 4) B vuelve a ser réplica
docker exec "$(C portal-db-b)" sh -c 'mv /etc/acc/DR-ACTIVO /etc/acc/DR-finalizado-$(date +%Y%m%d%H%M) 2>/dev/null; true'
paso "marca DR retirada: REINICIAR el nodo portal-db-b (reanuda la réplica) y APAGAR portal-b, authelia-b, gate-b, archivo-b"
