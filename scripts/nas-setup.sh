#!/bin/bash
# NAS (MinIO) de los dos sitios: credenciales/LDAP desde .env, bucket inmutable (Object Lock) y réplica A -> B.
# Idempotente. Uso: nas-setup.sh env    (escribe nas.env en ambos NAS; luego reiniciar los nodos)
#                   nas-setup.sh config (buckets, retención, réplica, política LDAP)
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
BASE="DC=ad,DC=alcaldia,DC=lab"
if [ "${1:-}" = env ]; then
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
mcx 'for s in a b; do mc mb --ignore-existing --with-lock $s/respaldos >/dev/null && mc retention set --default COMPLIANCE 7d $s/respaldos >/dev/null && echo "$s/respaldos: Object Lock COMPLIANCE 7d (nadie, ni root, borra versiones antes de 7 días)"; done'
# la regla lleva las credenciales de B: se rehace siempre (p. ej. tras rotar MINIO_ROOT_PASS)
mcx 'mc replicate rm --all --force a/respaldos >/dev/null 2>&1; mc replicate add a/respaldos --remote-bucket "http://admin-nas:$RP@10.20.60.10:9000/respaldos" --replicate "delete-marker,existing-objects"   # sin "delete": no se propagan borrados de versiones >/dev/null; mc replicate status a/respaldos >/dev/null && echo "réplica a/respaldos -> b/respaldos activa"'
for s in a b; do mcx "out=\$(mc idp ldap policy attach $s consoleAdmin --group='CN=nas-admins,CN=Users,$BASE' 2>&1) || echo \"\$out\" | grep -q 'already in effect' && echo '$s: nas-admins -> consoleAdmin'"; done
# --- F9: cuentas para restic (en ambos NAS, para poder restaurar desde B en un DR) ---
#  restic          -> lee/escribe/borra objetos (restic necesita borrar sus locks), pero NO puede borrar VERSIONES,
#                     ni tocar la retención: con Object Lock + versionado, un ransomware con esta clave no destruye copias.
#  restic-lectura  -> solo lectura (Zabbix comprueba la antigüedad del último respaldo)
docker exec -i "$A" sh -c 'cat > /tmp/pol-restic.json' <<'EOP'
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation","s3:GetBucketObjectLockConfiguration"],"Resource":["arn:aws:s3:::respaldos","arn:aws:s3:::respaldos/*"]},
 {"Effect":"Deny","Action":["s3:DeleteObjectVersion","s3:PutObjectRetention","s3:BypassGovernanceRetention","s3:PutBucketObjectLockConfiguration","s3:PutBucketVersioning","s3:DeleteBucket","s3:PutLifecycleConfiguration"],"Resource":["arn:aws:s3:::respaldos","arn:aws:s3:::respaldos/*"]}]}
EOP
docker exec -i "$A" sh -c 'cat > /tmp/pol-restic-ro.json' <<'EOP'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::respaldos","arn:aws:s3:::respaldos/*"]}]}
EOP
# Con LDAP activo MinIO no admite usuarios internos -> cuentas de servicio (access keys) con política en línea
docker exec -e K="$RESTIC_S3_KEY" -e R="$RESTIC_RO_KEY" "$A" sh -c 'for s in a b; do
  for u in restic:K:pol-restic restic-lectura:R:pol-restic-ro; do ak=${u%%:*}; v=$(echo $u | cut -d: -f2); pol=$(echo $u | cut -d: -f3); eval sk=\$$v
    if mc admin user svcacct info $s "$ak" >/dev/null 2>&1; then mc admin user svcacct edit $s "$ak" --secret-key "$sk" --policy /tmp/$pol.json >/dev/null
    else mc admin user svcacct add $s admin-nas --access-key "$ak" --secret-key "$sk" --policy /tmp/$pol.json >/dev/null; fi
  done; echo "$s: cuentas de servicio restic / restic-lectura"; done'
docker exec -e AWS_ACCESS_KEY_ID=restic -e AWS_SECRET_ACCESS_KEY="$RESTIC_S3_KEY" -e RESTIC_PASSWORD="$RESTIC_PASSWORD" "$A" sh -c \
  'export RESTIC_REPOSITORY=s3:http://127.0.0.1:9000/respaldos/repo; restic cat config >/dev/null 2>&1 && echo "repositorio restic: ya existe" || { restic init >/dev/null && echo "repositorio restic: creado (cifrado AES-256)"; }'
