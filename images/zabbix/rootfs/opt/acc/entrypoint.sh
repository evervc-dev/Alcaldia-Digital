#!/bin/sh
(
  touch /tmp/zabbix-acc.log && chown zabbix /tmp/zabbix-acc.log   # el proceso corre como zabbix
  until [ -s /etc/acc/zbx.env ]; do sleep 2; done
  set -a; . /etc/acc/zbx.env; set +a
  # comprobaciones externas (F9): el script vive en el volumen /etc/acc; el enlace se pierde al recrear el contenedor
  mkdir -p /usr/lib/zabbix/externalscripts; for f in /etc/acc/*.sh; do [ -f "$f" ] && ln -sf "$f" /usr/lib/zabbix/externalscripts/; done
  # el log lo abre el propio usuario zabbix: nginx reabre /dev/stdout y falla si el fd pertenece a root
  while true; do su-exec zabbix sh -c "exec $ACC_CMD >> /tmp/zabbix-acc.log 2>&1"; echo "$(date) reinicio" >> /tmp/zabbix-acc.log; sleep 5; done
) &
echo "[acc] Zabbix arrancará cuando exista /etc/acc/zbx.env"
exec /bin/bash -l
