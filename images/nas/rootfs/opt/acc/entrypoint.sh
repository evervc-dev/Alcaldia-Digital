#!/bin/bash
# Credenciales y LDAP en /data/.acc/nas.env (volumen persistente, escrito desde .env del host; no versionado)
mkdir -p /data/minio /data/.acc
if [ -f /data/.acc/nas.env ]; then
  set -a; . /data/.acc/nas.env; set +a
  minio server /data/minio --address :9000 --console-address :9001 > /var/log/minio.log 2>&1 &
  echo "[acc] MinIO iniciado (API :9000, consola :9001)"
else
  echo "[acc] falta /data/.acc/nas.env: MinIO no iniciado"
fi
exec /bin/bash -l
