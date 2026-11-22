#!/bin/bash
# Espera POSTGRES_* en /etc/acc/pg.env y lanza el entrypoint oficial. Consola: bash.
# Modo réplica (Site B): si pg.env define REPLICA_DE=<ip>, copia la BD primaria cada REPLICA_CADA s (defecto 3600 = RPO 1 h)
# con pg_dump/pg_restore y deja la hora de la última copia correcta en /var/lib/postgresql/data/replica_ok.
(
  until [ -s /etc/acc/pg.env ]; do sleep 2; done
  set -a; . /etc/acc/pg.env; set +a
  exec docker-entrypoint.sh postgres -c listen_addresses='*' -c wal_level=replica -c max_wal_senders=5 > /var/log/postgres.log 2>&1
) &
(
  until [ -s /etc/acc/pg.env ]; do sleep 2; done
  set -a; . /etc/acc/pg.env; set +a
  [ -z "${REPLICA_DE:-}" ] && exit 0
  until pg_isready -q -h 127.0.0.1; do sleep 3; done
  while true; do
    # DR (P-A): con /etc/acc/DR-ACTIVO esta BD es la primaria y NO se pisa con copias del Site A
    if [ -f /etc/acc/DR-ACTIVO ]; then sleep 60; continue; fi
    if PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h "$REPLICA_DE" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/replica.dump 2>>/var/log/replica.log \
       && PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists /tmp/replica.dump 2>>/var/log/replica.log; then
      date -Is > "${PGDATA:-/var/lib/postgresql/data}/replica_ok"; echo "$(date -Is) réplica OK desde $REPLICA_DE" >> /var/log/replica.log
      sleep "${REPLICA_CADA:-3600}"
    else echo "$(date -Is) réplica FALLÓ desde $REPLICA_DE (reintento en 5 min)" >> /var/log/replica.log
      sleep 300   # tras un fallo (p. ej. corte A<->B) no esperar la hora completa: protege el RPO
    fi
  done
) &
echo "[acc] PostgreSQL arrancará cuando exista /etc/acc/pg.env"
for d in /etc/acc /var/lib/samba/acc /config/acc /data/.acc; do [ -x $d/respaldo.sh ] && { $d/respaldo.sh bucle & break; }; done   # F9: respaldo diario
exec /bin/bash -l
