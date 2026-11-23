#!/bin/bash
# Credenciales y LDAP en /data/.acc/nas.env (volumen persistente, escrito desde .env del host; no versionado)
# MinIO desactiva LDAP para siempre si al arrancar no alcanza el DC (arranque en frío: los FW aún no están).
# Por eso corre en un bucle y un vigilante lo reinicia en cuanto el DC responde por LDAPS.
mkdir -p /data/minio /data/.acc
if [ -f /data/.acc/nas.env ]; then
  set -a; . /data/.acc/nas.env; set +a
  LDAP=${MINIO_IDENTITY_LDAP_SERVER_ADDR%:*}
  ( while true; do minio server /data/minio --address :9000 --console-address :9001 > /var/log/minio.log 2>&1; sleep 3; done ) &
  ( while true; do sleep 60
      if grep -q "LDAP configuration will be disabled" /var/log/minio.log 2>/dev/null && nc -z -w3 "$LDAP" 636 2>/dev/null; then
        echo "$(date -Is) DC $LDAP alcanzable: reiniciando MinIO para activar LDAP" >> /var/log/nas-vigia.log; pkill -x minio
      fi; done ) &
  # alias de mc "a" (nas-a) y "b" (nas-b) para scripts y lab-check: se pierden al recrear el contenedor
  ( if ip -4 a | grep -q '10\.10\.60\.10/'; then A=127.0.0.1; B=10.20.60.10; else A=10.10.60.10; B=127.0.0.1; fi
    until mc alias set a "http://$A:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do sleep 10; done
    until mc alias set b "http://$B:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do sleep 30; done ) &
  echo "[acc] MinIO iniciado (API :9000, consola :9001)"
elif [ -f /data/.acc/cinta.env ]; then
  /opt/acc/cinta.sh > /var/log/cinta.log 2>&1 &   # nodo tape: copia a cartucho al encender
  echo "[acc] cinta LTO: copiando nas-b a un cartucho nuevo (ver /data/cartuchos/registro.log)"
else
  echo "[acc] falta /data/.acc/nas.env: MinIO no iniciado"
fi
for d in /etc/acc /var/lib/samba/acc /config/acc /data/.acc; do [ -x $d/respaldo.sh ] && { $d/respaldo.sh bucle & break; }; done   # F9: respaldo diario
exec /bin/bash -l
