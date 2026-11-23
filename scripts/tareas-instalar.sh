#!/bin/bash
# Instala (idempotente) el temporizador systemd --user que lanza scripts/tareas.sh cada hora y el simulador de la sala (acc-sensores).
# Corre mientras tu sesión esté abierta (el lab también). Desinstalar: tareas-instalar.sh quitar
set -euo pipefail; cd "$(dirname "$0")/.."; REPO=$(pwd); D=~/.config/systemd/user
if [ "${1:-}" = quitar ]; then systemctl --user disable --now acc-tareas.timer acc-sensores.service || true; rm -f "$D"/acc-tareas.{service,timer} "$D"/acc-sensores.service; systemctl --user daemon-reload; echo "temporizador quitado"; exit 0; fi
mkdir -p "$D"
sed "s|@REPO@|$REPO|" config/systemd/acc-tareas.service > "$D/acc-tareas.service"
cp config/systemd/acc-tareas.timer "$D/"
sed "s|@REPO@|$REPO|" config/systemd/acc-sensores.service > "$D/acc-sensores.service"   # sala simulada (UPS/ambiente)
systemctl --user daemon-reload && systemctl --user enable --now acc-tareas.timer && systemctl --user enable --now acc-sensores.service
systemctl --user list-timers acc-tareas.timer --no-pager
