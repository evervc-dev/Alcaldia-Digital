#!/bin/bash
# Arranca nginx cuando exista una configuración válida en conf.d (la entrega deploy-config.sh)
(
  until ls /etc/nginx/conf.d/*.conf >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; do sleep 3; done
  while true; do nginx -g 'daemon off;' >> /var/log/nginx-acc.log 2>&1; sleep 5; done
) &
echo "[acc] nginx arrancará cuando conf.d tenga una configuración válida (nginx -t)"
exec /bin/bash -l
