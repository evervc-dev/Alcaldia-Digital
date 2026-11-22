#!/bin/bash
# F9: instala el respaldo diario (restic -> nas-a, replicado a nas-b) en cada equipo con datos. Idempotente.
#   - respaldo.sh + respaldo.env (secretos desde .env, modo 600) en el VOLUMEN persistente de cada equipo
#   - binario restic en los contenedores en marcha (las imágenes nuevas ya lo traen)
#   - arranca el bucle diario (HORA_UTC; 08 = 02:00 hora de El Salvador) y, con "ahora", un primer respaldo
#   - Zabbix: restic + credenciales de SOLO LECTURA para comprobar la antigüedad del último respaldo
# Uso: respaldo-setup.sh [ahora]
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
C() { echo "GNS3.$1.$PID"; }
REPO_A="s3:http://10.10.60.10:9000/respaldos/repo"

# equipo  directorio-persistente  TIPO  RUTAS  HORA_UTC  extra
EQUIPOS=(
  "ts1|/var/lib/samba/acc|rutas|/home|08|"
  "archivo|/config/acc|rutas|/srv /database|08|"
  "portal-db|/etc/acc|pgdump||08|. /etc/acc/pg.env"
  "dc1|/var/lib/samba/acc|samba||08|"
  "nas-a|/data/.acc|mantenimiento||10|"
)
for e in "${EQUIPOS[@]}"; do
  IFS='|' read -r n dir tipo rutas hora extra <<<"$e"
  repo=$REPO_A; [ "$n" = nas-a ] && repo="s3:http://127.0.0.1:9000/respaldos/repo"
  docker inspect "$(C $n)" >/dev/null 2>&1 || { echo "! $n no está en marcha"; continue; }
  # binario (solo hace falta en contenedores creados con la imagen anterior)
  docker exec "$(C $n)" sh -c 'restic version >/dev/null 2>&1' || \
    docker exec -i "$(C $n)" sh -c 'mkdir -p /usr/local/bin && cat > /usr/local/bin/restic && chmod 755 /usr/local/bin/restic' < <(docker run --rm --entrypoint cat restic/restic:0.17.3 /usr/bin/restic)
  docker exec -i "$(C $n)" sh -c "mkdir -p $dir && cat > $dir/respaldo.sh && chmod 700 $dir/respaldo.sh" < config/respaldo/respaldo.sh
  {
    printf "# Respaldo de %s (generado por respaldo-setup.sh desde .env; NO versionar)\n" "$n"
    printf "RESTIC_REPOSITORY='%s'\nRESTIC_PASSWORD='%s'\nAWS_ACCESS_KEY_ID='restic'\nAWS_SECRET_ACCESS_KEY='%s'\n" "$repo" "$RESTIC_PASSWORD" "$RESTIC_S3_KEY"
    printf "EQUIPO='%s'\nTIPO='%s'\nRUTAS='%s'\nHORA_UTC='%s'\n" "$n" "$tipo" "$rutas" "$hora"
    if [ -n "$extra" ]; then echo "$extra"; fi
  } | docker exec -i "$(C $n)" sh -c "umask 077; cat > $dir/respaldo.env"
  # (re)arrancar el bucle diario ([r] evita que pkill se encuentre a sí mismo)
  docker exec "$(C $n)" sh -c "pkill -f '[r]espaldo.sh bucle' 2>/dev/null; true"
  docker exec -d "$(C $n)" "$dir/respaldo.sh" bucle
  echo "$n: respaldo diario instalado ($tipo, $(printf '%02d' $((10#$hora - 6))):00 hora local)"
done

# Zabbix: comprueba la antigüedad del último respaldo de cada equipo (credenciales de solo lectura)
Z=$(C zbx-server)
docker exec "$Z" sh -c 'restic version >/dev/null 2>&1' || \
  docker exec -i "$Z" sh -c 'mkdir -p /usr/local/bin && cat > /usr/local/bin/restic && chmod 755 /usr/local/bin/restic' < <(docker run --rm --entrypoint cat restic/restic:0.17.3 /usr/bin/restic)
printf "RESTIC_REPOSITORY='%s'\nRESTIC_PASSWORD='%s'\nAWS_ACCESS_KEY_ID='restic-lectura'\nAWS_SECRET_ACCESS_KEY='%s'\n" "$REPO_A" "$RESTIC_PASSWORD" "$RESTIC_RO_KEY" \
  | docker exec -i "$Z" sh -c 'umask 077; cat > /etc/acc/restic.env; chown zabbix /etc/acc/restic.env'
docker exec -i "$Z" sh -c 'D=/usr/lib/zabbix/externalscripts; mkdir -p $D; cat > /etc/acc/restic-ultimo.sh; chmod 755 /etc/acc/restic-ultimo.sh; ln -sf /etc/acc/restic-ultimo.sh $D/restic-ultimo.sh' <<'EOS'
#!/bin/sh
# Zabbix (comprobación externa): JSON del último snapshot restic del equipo $1 (sin bloquear el repositorio)
set -a; . /etc/acc/restic.env; set +a
exec restic snapshots --no-lock --no-cache --host "$1" --latest 1 --json 2>&1
EOS
echo "zbx-server: comprobación de respaldos instalada (solo lectura)"

if [ "${1:-}" = ahora ]; then
  echo "== primer respaldo"
  for n in ts1 archivo portal-db dc1; do
    dir=$(printf '%s\n' "${EQUIPOS[@]}" | awk -F'|' -v n=$n '$1==n{print $2}')
    printf "%s: " "$n"; docker exec "$(C $n)" "$dir/respaldo.sh" ahora | sed 's/^[^ ]* //'
  done
fi

# Cinta LTO simulada (nodo tape, Site B): credenciales de SOLO LECTURA de nas-b. Se enciende -> copia -> se apaga.
if docker inspect "$(C tape)" >/dev/null 2>&1; then
  printf "NAS_B='10.20.60.10'\nCLAVE_LECTURA='%s'\n" "$RESTIC_RO_KEY" | docker exec -i "$(C tape)" sh -c 'mkdir -p /data/.acc; umask 077; cat > /data/.acc/cinta.env'
  echo "tape: cinta.env instalado (al reiniciar el nodo grabará un cartucho)"
fi
