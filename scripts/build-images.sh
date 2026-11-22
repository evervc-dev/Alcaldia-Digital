#!/bin/bash
# Construye TODAS las imágenes propias acc/*. El orden importa:
#   kit-sede hereda de router; puesto-linux de escritorio; restic/restic:0.17.3 (estático) aporta restic a
#   escritorio, samba-dc, pg, archivo y zabbix (COPY --from=restic/restic).
# Uso: build-images.sh [imagen...]   (sin argumentos: todas)
set -euo pipefail
cd "$(dirname "$0")/../images"
ORDEN="router kit-sede pc pc-gui nas samba-dc escritorio puesto-linux pg portal gate authelia nginx cloudflared lam archivo zabbix"
for r in ${*:-$ORDEN}; do
  if [ "$r" = zabbix ]; then
    echo "== acc/zabbix-server:1.0"; docker build -q -t acc/zabbix-server:1.0 --build-arg BASE=zabbix/zabbix-server-pgsql:alpine-7.0-latest \
      --build-arg ACC_CMD="/usr/bin/docker-entrypoint.sh /usr/sbin/zabbix_server --foreground -c /etc/zabbix/zabbix_server.conf" zabbix
    echo "== acc/zabbix-web:1.0"; docker build -q -t acc/zabbix-web:1.0 --build-arg BASE=zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest \
      --build-arg ACC_CMD="docker-entrypoint.sh" zabbix
  else
    echo "== acc/$r:1.0"; docker build -q -t "acc/$r:1.0" "$r"
  fi
done
docker images 'acc/*'
