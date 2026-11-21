#!/bin/bash
# Genera config/opnsense/root.hash (SHA-512 crypt) desde OPNSENSE_ROOT_PASS del .env, sin mostrarlo.
# El FW lo descarga (fetch) y set-root-pass.php lo instala y lo borra. Borrar el .hash después.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
: "${OPNSENSE_ROOT_PASS:?falta OPNSENSE_ROOT_PASS en .env}"
printf '%s' "$OPNSENSE_ROOT_PASS" | openssl passwd -6 -stdin > config/opnsense/root.hash
chmod 600 config/opnsense/root.hash; chmod o+r config/opnsense/root.hash
echo "hash generado ($(wc -c < config/opnsense/root.hash) bytes)"
