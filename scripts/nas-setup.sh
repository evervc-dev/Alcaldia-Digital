#!/bin/bash
# NAS (MinIO) de los dos sitios: credenciales/LDAP desde .env, bucket inmutable (Object Lock) y réplica A -> B.
# Idempotente. Uso: nas-setup.sh env    (escribe nas.env en ambos NAS; luego reiniciar los nodos)
#                   nas-setup.sh config (buckets, retención, réplica, política LDAP)
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
BASE="DC=ad,DC=alcaldia,DC=lab"
if [ "$1" = env ]; then
  for pair in "nas-a 10.10.20.10" "nas-b 10.20.20.10"; do set -- $pair
    docker exec -i "GNS3.$1.$PID" sh -c 'mkdir -p /data/.acc && umask 077 && cat > /data/.acc/nas.env' <<EOV
MINIO_ROOT_USER='admin-nas'
MINIO_ROOT_PASSWORD='$MINIO_ROOT_PASS'
MINIO_IDENTITY_LDAP_SERVER_ADDR='$2:636'
MINIO_IDENTITY_LDAP_TLS_SKIP_VERIFY='on'
MINIO_IDENTITY_LDAP_LOOKUP_BIND_DN='CN=svc-lectura,CN=Users,$BASE'
MINIO_IDENTITY_LDAP_LOOKUP_BIND_PASSWORD='$SVC_LDAP_PASS'
MINIO_IDENTITY_LDAP_USER_DN_SEARCH_BASE_DN='CN=Users,$BASE'
MINIO_IDENTITY_LDAP_USER_DN_SEARCH_FILTER='(sAMAccountName=%s)'
MINIO_IDENTITY_LDAP_GROUP_SEARCH_BASE_DN='$BASE'
MINIO_IDENTITY_LDAP_GROUP_SEARCH_FILTER='(&(objectclass=group)(member=%d))'
MINIO_PROMETHEUS_AUTH_TYPE='public'   # métricas de capacidad para Zabbix (solo lectura, sin datos)
EOV
    echo "$1: nas.env escrito (LDAP -> $2)"; done
  exit 0
fi
A="GNS3.nas-a.$PID"
mcx() { docker exec -e RP="$MINIO_ROOT_PASS" "$A" sh -c "$1"; }
mcx 'mc alias set a http://127.0.0.1:9000 admin-nas "$RP" >/dev/null && mc alias set b http://10.20.60.10:9000 admin-nas "$RP" >/dev/null && echo "alias a/b OK"'
mcx 'for s in a b; do mc mb --ignore-existing --with-lock $s/respaldos >/dev/null && mc retention set --default GOVERNANCE 7d $s/respaldos >/dev/null && echo "$s/respaldos: Object Lock GOVERNANCE 7d"; done'
mcx 'mc replicate ls a/respaldos 2>/dev/null | grep -q 10.20.60.10 || mc replicate add a/respaldos --remote-bucket "http://admin-nas:$RP@10.20.60.10:9000/respaldos" --replicate "delete,delete-marker,existing-objects" >/dev/null; mc replicate status a/respaldos >/dev/null && echo "réplica a/respaldos -> b/respaldos activa"'
for s in a b; do mcx "out=\$(mc idp ldap policy attach $s consoleAdmin --group='CN=nas-admins,CN=Users,$BASE' 2>&1) || echo \"\$out\" | grep -q 'already in effect' && echo '$s: nas-admins -> consoleAdmin'"; done
