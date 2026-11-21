#!/bin/sh
# /config/configuration.yml se entrega desde .env (scripts/services-setup.sh); no se versiona con secretos
(
  until [ -s /config/configuration.yml ]; do sleep 2; done
  exec authelia --config /config/configuration.yml > /config/authelia.log 2>&1
) &
echo "[acc] Authelia arrancará cuando exista /config/configuration.yml"
exec /bin/sh
