#!/bin/bash
# Tareas programadas del laboratorio (las lanza el temporizador systemd --user acc-tareas.timer cada hora).
# Cada tarea se ejecuta solo si LE TOCA (pasó su periodo desde el último éxito) y el lab está encendido:
#   configs : respaldo de configuraciones de red (backup-configs.sh) + commit local de configs/   cada 24 h
#   cinta   : enciende el nodo 'tape', graba un cartucho desde nas-b y lo APAGA (air gap)           cada 7 días
# El resultado (1 = OK, 0 = fallo) se envía a Zabbix (host "tareas-programadas", trapper acc.tarea[...]).
# Uso: tareas.sh                 (lo que toque)
#      tareas.sh ahora [configs|cinta]   (forzar ya, p. ej. en la defensa)
# Registro: ~/.local/state/acc/tareas.log
set -uo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
C() { echo "GNS3.$1.$PID"; }
ST=~/.local/state/acc; mkdir -p "$ST"; LOG=$ST/tareas.log
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
FORZAR=0; SOLO=""; [ "${1:-}" = ahora ] && { FORZAR=1; SOLO=${2:-}; }

exec 9>"$ST/tareas.lock"; flock -n 9 || { log "otra ejecución en curso"; exit 0; }

toca() { # tarea periodo_s
  [ -n "$SOLO" ] && [ "$SOLO" != "$1" ] && return 1
  [ $FORZAR = 1 ] && return 0
  local u; u=$(cat "$ST/$1.ok" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - u )) -ge "$2" ]
}
encendido() { for n in "$@"; do docker inspect -f '{{.State.Running}}' "$(C "$n")" 2>/dev/null | grep -q true || return 1; done; }
zabbix() { # tarea valor
  docker exec "$(C zbx-server)" zabbix_sender -z 127.0.0.1 -s tareas-programadas -k "acc.tarea[$1]" -o "$2" >/dev/null 2>&1 \
    || log "  (aviso: no se pudo informar a Zabbix)"
}
resultado() { # tarea ok(0/1)
  if [ "$2" = 1 ]; then date +%s > "$ST/$1.ok"; log "$1: OK"; else log "$1: FALLO"; fi
  zabbix "$1" "$2"
}

# ---------- 0) bucles de respaldo ----------
# El nodo archivo usa la imagen original de filebrowser (sin enganche ni restic): tras reabrir el proyecto hay que reinstalarlos.
for n in ts1 archivo portal-db dc1 zbx-db glpi-db glpi; do
  encendido "$n" || continue
  if ! docker exec "$(C "$n")" sh -c 'for c in /proc/[0-9]*/cmdline; do tr "\0" " " < $c 2>/dev/null | grep -q "[r]espaldo.sh bucle" && exit 0; done; exit 1'; then
    log "respaldo: $n sin bucle; se reinstalan"; encendido nas-a zbx-server && bash scripts/respaldo-setup.sh >> "$LOG" 2>&1; break
  fi
done

# ---------- 1) configuraciones de red ----------
if toca configs 86400; then
  if ! encendido nas-a isp1; then log "configs: lab apagado (nas-a/isp1): reintento en la próxima hora"
  else
    out=$(bash scripts/backup-configs.sh 2>&1); rc=$?; echo "$out" | sed 's/^/    /' >> "$LOG"
    nfw=$(grep -c 'config.xml (' <<<"$out")
    if [ $rc = 0 ] && [ "$nfw" = 3 ]; then
      if [ -e .git/MERGE_HEAD ] || [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
        log "configs: git en merge/rebase, no se hace commit (configs/ queda actualizado)"
      else
        git add configs
        if git diff --cached --quiet -- configs; then log "configs: sin cambios respecto al último commit"
        elif git commit -q -m "configs: respaldo automático $(date +%F_%H%M)" -- configs; then log "configs: commit local hecho (súbelo con push)"
        else log "configs: no se pudo hacer el commit (configs/ queda actualizado)"; fi
      fi
      resultado configs 1
    else log "configs: rc=$rc, firewalls respaldados=$nfw/3"; resultado configs 0; fi
  fi
fi

# ---------- 2) cinta (nodo tape) ----------
gns3() { # método ruta
  [ -n "${TOKEN:-}" ] || TOKEN=$(curl -fsS -X POST "$GNS3_URL/v3/access/users/authenticate" -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,os;print(json.dumps({"username":os.environ["GNS3_USER"],"password":os.environ["GNS3_PASS"]}))')" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])') || return 1
  curl -fsS -X "$1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$GNS3_URL/v3/projects/$PID$2" ${3:+-d "$3"}
}
if toca cinta 604800; then
  if ! encendido nas-b; then log "cinta: nas-b apagado: reintento en la próxima hora"
  elif ! gns3 GET "" 2>/dev/null | grep -q '"status": *"opened"'; then log "cinta: proyecto ACC-Lab no abierto en GNS3: reintento en la próxima hora"
  else
    NID=$(gns3 GET /nodes | python3 -c 'import sys,json;print(next(n["node_id"] for n in json.load(sys.stdin) if n["name"]=="tape"))')
    if encendido tape; then   # quedó encendido (p. ej. tras "Start all"): apagar antes, la grabación ocurre al ARRANCAR
      gns3 POST "/nodes/$NID/stop" '{}' >/dev/null; sleep 5; log "cinta: tape estaba encendido (¡no debería!): apagado y se vuelve a encender"
    fi
    T0=$(date +%s); ok=0
    gns3 POST "/nodes/$NID/start" '{}' >/dev/null && log "cinta: nodo tape encendido, grabando cartucho..."
    for i in $(seq 1 90); do   # hasta 15 min
      sleep 10
      m=$(docker exec "$(C tape)" stat -c %Y /data/cartuchos/registro.log 2>/dev/null || echo 0)
      if [ "$m" -ge "$T0" ]; then
        linea=$(docker exec "$(C tape)" tail -1 /data/cartuchos/registro.log); log "  $linea"
        grep -q ' OK cartucho' <<<"$linea" && ok=1; break
      fi
    done
    gns3 POST "/nodes/$NID/stop" '{}' >/dev/null && log "cinta: nodo tape APAGADO (fuera de línea)" || log "cinta: ¡no se pudo apagar tape! apágalo a mano"
    resultado cinta $ok
  fi
# ---------- 3) air gap: tape encendido por un "Start all" ----------
# Al arrancar graba un cartucho (válido); en cuanto lo termina se apaga: la cinta debe quedar fuera de línea.
elif encendido tape; then
  ini=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$(C tape)")" +%s)
  m=$(docker exec "$(C tape)" stat -c %Y /data/cartuchos/registro.log 2>/dev/null || echo 0)
  if [ "$m" -ge "$ini" ] || [ $(( $(date +%s) - ini )) -gt 1200 ]; then
    NID=$(gns3 GET /nodes | python3 -c 'import sys,json;print(next(n["node_id"] for n in json.load(sys.stdin) if n["name"]=="tape"))')
    linea=$(docker exec "$(C tape)" tail -1 /data/cartuchos/registro.log 2>/dev/null)
    gns3 POST "/nodes/$NID/stop" '{}' >/dev/null && log "cinta: tape estaba encendido (Start all); cartucho del arranque: ${linea:-ninguno}. APAGADO (fuera de línea)"
  fi
fi
exit 0
