#!/bin/bash
# Entrega configuración con secretos (desde .env) a los servicios del Site A. Nunca imprime secretos. Idempotente.
# Después: reiniciar los nodos afectados con gns3-mcp.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
put() { docker exec -i "GNS3.$1.$PID" sh -c "mkdir -p \$(dirname '$2') && umask 077 && cat > '$2'"; echo "  $1: $2"; }
SITE=${SITE:-A}; SFX=$([ "$SITE" = B ] && echo "-b" || echo "")
DBIP=$([ "$SITE" = B ] && echo 10.20.20.22 || echo 10.10.20.22)
REPL=$([ "$SITE" = B ] && printf "REPLICA_DE='10.10.20.22'\nREPLICA_CADA='3600'\n" || true)
{ printf "POSTGRES_USER='portal'\nPOSTGRES_PASSWORD='%s'\nPOSTGRES_DB='portal'\nPGDATA='/var/lib/postgresql/data/pgdata'\n" "$PORTAL_DB_PASS"; printf '%s' "$REPL"; } | put portal-db$SFX /etc/acc/pg.env
printf "DATABASE_URL='postgresql://portal:%s@%s/portal'\nPORTAL_SITE='Site %s'\n" "$PORTAL_DB_PASS" "$DBIP" "$SITE" | put portal$SFX /etc/acc/portal.env
TOK_VAR="CF_TUNNEL_TOKEN_$SITE"; printf '%s' "${!TOK_VAR}" | put cloudflared-$(echo $SITE | tr A-Z a-z) /etc/acc/tunnel.token
# --- gate y authelia (en B quedan en espera: se encienden en DR) ---
GATE=gate$SFX; AUTH=authelia$SFX
LDAPS=$([ "$SITE" = B ] && echo "ldaps://10.20.20.10,ldaps://10.10.20.10" || echo "ldaps://10.10.20.10,ldaps://10.20.20.10")
put $GATE /etc/acc/horario.conf < config/politicas/horario.conf
printf "LDAP_BIND_DN=svc-lectura@ad.alcaldia.lab\nLDAP_BIND_PW=%s\nLDAP_URL=%s\nAUTHELIA_URL=http://%s:9091\n" "$SVC_LDAP_PASS" "$LDAPS" "$([ "$SITE" = B ] && echo 10.20.20.11 || echo 10.10.20.11)" | put $GATE /etc/acc/gate.env
export LDAP_ADDR="ldaps://$([ "$SITE" = B ] && echo 10.20.20.10 || echo 10.10.20.10):636" PG_ADDR=$DBIP
if [ "$SITE" = B ]; then export NOTIFIER="  filesystem:
    filename: '/config/notificaciones.txt'"
else export NOTIFIER="  smtp:
    address: 'smtp://10.10.20.32:1025'
    sender: 'Alcaldia Digital <no-reply@evervc.dev>'
    disable_require_tls: true
    disable_starttls: true"; fi
python3 - <<'PY2' | put $AUTH /config/configuration.yml
import os,re,sys
t=open("config/authelia/configuration.yml.tpl").read()
sys.stdout.write(re.sub(r"\$\{(\w+)\}", lambda m: os.environ[m.group(1)], t))
PY2
put $AUTH /config/certs/ca.crt < config/pki/ca.crt
for l in es en; do put $AUTH /config/assets/locales/$l/portal.json < config/authelia/assets/locales/$l/portal.json; done
# --- LAM (solo Site A): perfil AD versionado + secretos ---
if [ "$SITE" = A ]; then
  put lam /etc/acc/lam-perfil.json < config/lam/lam-perfil.json
  printf "SVC_LDAP_PASS='%s'\nLAM_MASTER_PASS='%s'\n" "$SVC_LDAP_PASS" "$LAM_MASTER_PASS" | put lam /etc/acc/lam.env
fi
