#!/bin/sh
# /config/configuration.yml se entrega desde .env (scripts/services-setup.sh); no se versiona con secretos
(
  until [ -s /config/configuration.yml ]; do sleep 2; done
  while true; do   # reintenta: al reabrir el proyecto la BD o el DC pueden arrancar después
    authelia --config /config/configuration.yml >> /config/authelia.log 2>&1
    echo "$(date -Is) authelia terminó; reintento en 10 s" >> /config/authelia.log; sleep 10
  done
) &
echo "[acc] Authelia arrancará cuando exista /config/configuration.yml"
exec /bin/sh
