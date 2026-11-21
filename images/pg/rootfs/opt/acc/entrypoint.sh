#!/bin/bash
# Espera POSTGRES_* en /etc/acc/pg.env y lanza el entrypoint oficial. Consola: bash.
(
  until [ -s /etc/acc/pg.env ]; do sleep 2; done
  set -a; . /etc/acc/pg.env; set +a
  exec docker-entrypoint.sh postgres -c listen_addresses='*' -c wal_level=replica -c max_wal_senders=5 > /var/log/postgres.log 2>&1
) &
echo "[acc] PostgreSQL arrancará cuando exista /etc/acc/pg.env"
exec /bin/bash -l
