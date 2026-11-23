#!/bin/sh
# Respaldo con restic (F9). Uso: respaldo.sh bucle | ahora
# Vive en el volumen persistente del equipo junto a respaldo.env (lo instala scripts/respaldo-setup.sh).
# TIPO=rutas   -> RUTAS (homes de ts1, datos de archivo)
# TIPO=pgdump  -> pg_dumpall de la BD local (incluye roles)
# TIPO=mysqldump -> volcado completo de MariaDB (BD de GLPI), transacción consistente
# TIPO=samba   -> samba-tool domain backup offline (copia completa del AD, recuperable con 'domain backup restore')
# TIPO=mantenimiento (nas-a) -> retención (forget --prune) y verificación (check) del repositorio
# Hora: HORA_UTC (08 = 02:00 en El Salvador), o cada CADA_H horas si se define (RPO de 4 h de archivo y mesa, Fase 2).
# Retención (Fases 3 y 5): todo lo de las últimas 24 h + 30 diarias + 4 semanales + 12 mensuales.
D=$(cd "$(dirname "$0")" && pwd); set -a; . "$D/respaldo.env"; set +a
export RESTIC_CACHE_DIR=/tmp/restic-cache
LOG=/var/log/respaldo.log; TMP=/tmp/respaldo-acc; mkdir -p /var/log

uno() {
  rm -rf "$TMP"; mkdir -p "$TMP"
  case "$TIPO" in
    rutas)  restic backup -q --host "$EQUIPO" --tag "$EQUIPO" $EXCLUIR $RUTAS ;;
    pgdump) PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -h 127.0.0.1 -U "$POSTGRES_USER" > "$TMP/$EQUIPO.sql" \
              && restic backup -q --host "$EQUIPO" --tag "$EQUIPO" "$TMP" ;;
    mysqldump) MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --all-databases --single-transaction --routines --events > "$TMP/$EQUIPO.sql" \
              && restic backup -q --host "$EQUIPO" --tag "$EQUIPO" "$TMP" ;;
    samba)  samba-tool domain backup offline --targetdir="$TMP" >/dev/null 2>&1 \
              && restic backup -q --host "$EQUIPO" --tag "$EQUIPO" "$TMP" ;;
    mantenimiento) restic forget -q --keep-within 1d --keep-daily 30 --keep-weekly 4 --keep-monthly 12 --prune && restic check -q ;;
    *) echo "TIPO desconocido: $TIPO"; return 1 ;;
  esac
  rc=$?; rm -rf "$TMP"; return $rc
}

ejecutar() {
  t0=$(date +%s)
  if out=$(uno 2>&1); then echo "$(date -Iseconds) OK $EQUIPO ($TIPO) en $(( $(date +%s) - t0 )) s" >> $LOG
  else echo "$(date -Iseconds) FALLO $EQUIPO ($TIPO): $(echo "$out" | tail -2 | tr '\n' ' ')" >> $LOG; return 1; fi
}

case "${1:-ahora}" in
  ahora) ejecutar; tail -1 $LOG ;;
  bucle)
    [ -n "${CADA_H:-}" ] && { sleep 300; ejecutar; }   # RPO corto: al arrancar no esperar al siguiente tramo
    while true; do
      now=$(date +%s)
      if [ -n "${CADA_H:-}" ]; then P=$(( CADA_H * 3600 )); next=$(( now / P * P + P ))   # cada CADA_H horas en punto (UTC)
      else next=$(( now / 86400 * 86400 + ${HORA_UTC:-8} * 3600 )); [ $next -le $now ] && next=$(( next + 86400 )); fi
      sleep $(( next - now ))
      ejecutar || { sleep 1800; ejecutar; }   # un reintento a los 30 min
    done ;;
esac
