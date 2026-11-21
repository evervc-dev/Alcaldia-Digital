#!/bin/bash
# Entrega configuración con secretos (desde .env) a los servicios del Site A. Nunca imprime secretos. Idempotente.
# Después: reiniciar los nodos afectados con gns3-mcp.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
put() { docker exec -i "GNS3.$1.$PID" sh -c "mkdir -p \$(dirname '$2') && umask 077 && cat > '$2'"; echo "  $1: $2"; }
SITE=${SITE:-A}; SFX=$([ "$SITE" = B ] && echo "-b" || echo "")
DBIP=$([ "$SITE" = B ] && echo 10.20.20.22 || echo 10.10.20.22)
printf "POSTGRES_USER='portal'\nPOSTGRES_PASSWORD='%s'\nPOSTGRES_DB='portal'\nPGDATA='/var/lib/postgresql/data/pgdata'\n" "$PORTAL_DB_PASS" | put portal-db$SFX /etc/acc/pg.env
printf "DATABASE_URL='postgresql://portal:%s@%s/portal'\nPORTAL_SITE='Site %s'\n" "$PORTAL_DB_PASS" "$DBIP" "$SITE" | put portal$SFX /etc/acc/portal.env
TOK_VAR="CF_TUNNEL_TOKEN_$SITE"; printf '%s' "${!TOK_VAR}" | put cloudflared-$(echo $SITE | tr A-Z a-z) /etc/acc/tunnel.token
if [ "$SITE" = A ]; then
  put gate /etc/acc/horario.conf < config/politicas/horario.conf
  printf "LDAP_BIND_DN='svc-lectura@ad.alcaldia.lab'\nLDAP_BIND_PW='%s'\n" "$SVC_LDAP_PASS" | sed "s/'//g" | put gate /etc/acc/gate.env
  python3 - <<'PY' | put authelia /config/configuration.yml
import os,re,sys
t=open("config/authelia/configuration.yml.tpl").read()
sys.stdout.write(re.sub(r"\$\{(\w+)\}", lambda m: os.environ[m.group(1)], t))
PY
  put authelia /config/certs/ca.crt < config/pki/ca.crt
  for l in es en; do put authelia /config/assets/locales/$l/portal.json < config/authelia/assets/locales/$l/portal.json; done
fi
