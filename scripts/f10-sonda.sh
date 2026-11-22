#!/bin/bash
# F10: sonda de disponibilidad de extremo a extremo durante una prueba de falla (T2, T3, T8...).
# Mide cada ~0,5 s, en paralelo:  portal público (Internet -> Cloudflare -> túnel -> DMZ -> portal),
#   DNS del AD desde la Sede 1 (túneles + OSPF) y salida a Internet desde ADMIN (CARP + WAN).
# Uso: f10-sonda.sh <segundos> <archivo.log>     luego: f10-sonda.sh informe <archivo.log>
set -uo pipefail; cd "$(dirname "$0")/.."
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)

if [ "$1" = informe ]; then
  python3 -I - "$2" <<'PY'
import sys, collections
ev = collections.defaultdict(list)
for l in open(sys.argv[1]):
    t, sonda, r = l.split(); ev[sonda].append((float(t), r == "ok"))
print(f"{'sonda':<22}{'muestras':>9}{'fallos':>8}{'corte más largo':>18}")
for s, xs in sorted(ev.items()):
    xs.sort(); peor = 0.0; ini = None
    for t, ok in xs:
        if not ok and ini is None: ini = t
        if ok and ini is not None: peor = max(peor, t - ini); ini = None
    if ini is not None: peor = max(peor, xs[-1][0] - ini)
    print(f"{s:<22}{len(xs):>9}{sum(1 for _, o in xs if not o):>8}{peor:>16.1f} s")
PY
  exit 0
fi

DUR=$1; LOG=$2; : > "$LOG"; FIN=$(( $(date +%s) + DUR ))
sonda() { # nombre comando...
  local n=$1; shift
  while [ "$(date +%s)" -lt $FIN ]; do
    if timeout 3 "$@" >/dev/null 2>&1; then r=ok; else r=fallo; fi
    echo "$(date +%s.%N | cut -c1-14) $n $r" >> "$LOG"; sleep 0.5
  done
}
sonda portal-publico curl -sf -o /dev/null --max-time 2.5 https://portal.evervc.dev/ &
sonda sede1-dns-dc1 docker exec "GNS3.pc-01-a.$PID" dig +short +time=2 +tries=1 dc1.ad.alcaldia.lab @10.10.20.10 &
sonda admin-internet docker exec "GNS3.adm-pc.$PID" ping -c1 -W2 1.1.1.1 &
wait
