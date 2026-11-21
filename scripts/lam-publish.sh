#!/bin/bash
# Publica lam.evervc.dev en nginx-dmz (HTTPS) una vez emitido el certificado (scripts/cert-lam.sh). Idempotente.
set -euo pipefail; cd "$(dirname "$0")/.."
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename); C="GNS3.nginx-dmz.$PID"
CRT=secrets/lego/certificates/lam.evervc.dev.crt; KEY=secrets/lego/certificates/lam.evervc.dev.key
[ -s "$CRT" ] && [ -s "$KEY" ] || { echo "falta el certificado: ejecutar primero scripts/cert-lam.sh"; exit 1; }
docker exec "$C" mkdir -p /etc/nginx/conf.d/certs
docker exec -i "$C" sh -c 'cat > /etc/nginx/conf.d/certs/lam.evervc.dev.crt' < "$CRT"
docker exec -i "$C" sh -c 'umask 077; cat > /etc/nginx/conf.d/certs/lam.evervc.dev.key' < "$KEY"
docker exec -i "$C" sh -c 'cat > /etc/nginx/conf.d/lam.conf' < config/nodes/nginx-dmz/extra/lam.conf
docker exec "$C" sh -c 'nginx -t && nginx -s reload' && echo "lam.evervc.dev publicado (solo vía WARP)"
