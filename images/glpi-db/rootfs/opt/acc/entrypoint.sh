#!/bin/bash
# Espera MARIADB_* en /etc/acc/db.env y lanza el entrypoint oficial. Consola: bash.
(
  until [ -s /etc/acc/db.env ]; do sleep 2; done
  set -a; . /etc/acc/db.env; set +a
  while true; do docker-entrypoint.sh mariadbd >> /var/log/mariadb.log 2>&1; echo "$(date) reinicio" >> /var/log/mariadb.log; sleep 5; done
) &
echo "[acc] MariaDB arrancará cuando exista /etc/acc/db.env"
for d in /etc/acc; do [ -x $d/respaldo.sh ] && { $d/respaldo.sh bucle & break; }; done   # F9: respaldo diario
exec /bin/bash -l
