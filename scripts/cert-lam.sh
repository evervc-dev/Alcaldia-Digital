#!/bin/bash
# Certificado Let's Encrypt para lam.evervc.dev (validación DNS-01 con el token de Cloudflare del .env).
# Crea un registro TXT temporal _acme-challenge.lam.evervc.dev y lo borra al terminar. NO crea registros A/CNAME:
# lam.evervc.dev solo se resuelve por WARP (política DNS de Gateway). Salida en secrets/lego/ (no versionado).
# Renovación: volver a ejecutar el script (en v5, "run" también renueva si el certificado está por vencer; validez 90 días).
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a; mkdir -p secrets/lego
# lego v5: las opciones van DESPUÉS del subcomando (run).
docker run --rm -e CLOUDFLARE_DNS_API_TOKEN="$CF_API_TOKEN" -v "$PWD/secrets/lego:/.lego" goacme/lego:v5.5.2 \
  run --accept-tos --email ti@evervc.dev --dns cloudflare --dns.resolvers 1.1.1.1:53 --domains lam.evervc.dev --path /.lego
docker run --rm -v "$PWD/secrets/lego:/l" alpine:3.20 chown -R "$(id -u):$(id -g)" /l   # el contenedor escribe como root
chmod -R go-rwx secrets/lego; ls -l secrets/lego/certificates/lam.evervc.dev.crt secrets/lego/certificates/lam.evervc.dev.key
