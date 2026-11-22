#!/bin/bash
# Espera /etc/acc/glpi.env (GLPI_DB_*) y lanza el entrypoint oficial (instala o actualiza la BD) + supervisord como www-data.
(
  until [ -s /etc/acc/glpi.env ]; do sleep 2; done
  set -a; . /etc/acc/glpi.env; set +a
  chown -R www-data:www-data /var/glpi
  touch /tmp/glpi-acc.log && chown www-data /tmp/glpi-acc.log   # el log lo abre www-data (supervisord usa /dev/stdout)
  while true; do
    setpriv --reuid=www-data --regid=www-data --init-groups -- \
      sh -c 'exec /opt/glpi/entrypoint.sh /usr/bin/supervisord -c /etc/supervisor/supervisord.conf >> /tmp/glpi-acc.log 2>&1'
    echo "$(date) reinicio" >> /tmp/glpi-acc.log; sleep 10
  done
) &
echo "[acc] GLPI arrancará cuando exista /etc/acc/glpi.env (log: /tmp/glpi-acc.log)"
for d in /etc/acc; do [ -x $d/respaldo.sh ] && { $d/respaldo.sh bucle & break; }; done   # F9: respaldo diario
exec /bin/bash -l
