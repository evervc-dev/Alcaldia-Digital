#!/bin/bash
# Informe mensual de SLA (Fase 4 §2.3): disponibilidad medida (SLI) de S1–S6 frente al compromiso de la Tabla 4.
# Fuente: SLA de Zabbix (servicios S1–S6, alimentados por los disparadores de disponibilidad con la etiqueta servicio=Sx).
# Uso: sla-informe.sh [n.º de meses hacia atrás, por defecto 1 = el mes en curso]
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
docker exec -i -e ZABBIX_ADMIN_PASS -e MESES="${1:-1}" "GNS3.portal.$PID" python3 - <<'PY'
import json, os, urllib.request, datetime
U = "http://10.10.20.33:8080/api_jsonrpc.php"
def api(m, p, a=None):
    h = {"Content-Type": "application/json-rpc"}
    if a: h["Authorization"] = "Bearer " + a
    r = json.load(urllib.request.urlopen(urllib.request.Request(U, json.dumps({"jsonrpc": "2.0", "method": m, "params": p, "id": 1}).encode(), h)))
    if "error" in r: raise SystemExit(r["error"])
    return r["result"]
a = api("user.login", {"username": "Admin", "password": os.environ["ZABBIX_ADMIN_PASS"]})
fmt = lambda s: f"{s // 3600} h {s % 3600 // 60:02d} min"
print("Informe de SLA (Fase 4 §2.3) — disponibilidad medida por Zabbix en el horario de cada servicio")
print(f"{'Servicio':<30}{'Compromiso':>11}{'Mes':>10}{'Caído':>14}{'Margen del mes':>17}  Estado")
for sla in sorted(api("sla.get", {"output": ["slaid", "name", "slo"], "selectServiceTags": "extend"}, a), key=lambda x: x["name"]):
    r = api("sla.getsli", {"slaid": sla["slaid"], "periods": int(os.environ["MESES"])}, a)
    srv = {int(s["serviceid"]): s["name"] for s in api("service.get", {"serviceids": r["serviceids"], "output": ["serviceid", "name"]}, a)}
    for i, sid in enumerate(r["serviceids"]):
        for k, per in enumerate(r["periods"]):
            x = r["sli"][k][i]; slo = float(sla["slo"])
            horas_mes = 250 if "L-V" in sla["name"] else 730          # Fase 4 Tabla 3: 12 h x 20,83 días hábiles / 24 x 7
            permitido = horas_mes * 3600 * (100 - slo) / 100           # indisponibilidad permitida en el mes (Tabla 4)
            etiqueta = datetime.datetime.fromtimestamp(per["period_from"]).strftime("%m/%Y")
            # Fase 4 §2.1: se cumple mientras la caída del mes no supere la indisponibilidad permitida (Tabla 4).
            # «Mes» = disponibilidad proyectada sobre las horas de servicio del mes completo.
            mes = 100 * (1 - x["downtime"] / (horas_mes * 3600))
            medido = f"{mes:>8.2f}%"
            estado = "✔ cumple" if x["downtime"] <= permitido else "✘ INCUMPLE"
            if x["sli"] < 0: estado += " (aún sin horas medidas en su horario L-V 07-19)"
            print(f"{srv[int(sid)][:29]:<30}{slo:>10.1f}%{medido:>10}{fmt(x['downtime']):>14}{fmt(max(0, int(permitido - x['downtime']))):>17}  {estado} ({etiqueta})")
PY
