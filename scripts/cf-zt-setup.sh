#!/bin/bash
# Cloudflare Zero Trust para WARP (VPN de cliente del diseño). Idempotente. Correos en .env (WARP_EMAILS).
#  1) Login por PIN al correo  2) Inscripción de WARP solo para WARP_EMAILS  3) Proxy TCP/UDP de Gateway
#  4) Split tunnel: la red del laboratorio (10.0.0.0/8) va por WARP  5) Políticas de Gateway:
#     DNS lam.evervc.dev -> nginx-dmz interno; permitido solo a WARP_EMAILS: LAM (443) y ts1 (RDP); resto de 10.x bloqueado.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
API="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID"; H=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
j() { python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }
call() { local m=$1 u=$2 b=${3:-}; r=$(curl -sS "${H[@]}" -X "$m" "$API/$u" ${b:+-d "$b"}); echo "$r" | j 'sys.exit(0 if d.get("success") else (print("ERROR:", d.get("errors"), file=sys.stderr) or 1))' && echo "$r"; }
EMAILS_JSON=$(python3 -c 'import os,json;print(json.dumps([e.strip() for e in os.environ["WARP_EMAILS"].split(",") if e.strip()]))')
# 1) Proveedor de identidad: PIN por correo
IDP=$(call GET access/identity_providers | j 'print(next((i["id"] for i in d["result"] if i["type"]=="onetimepin"),""))')
[ -z "$IDP" ] && IDP=$(call POST access/identity_providers '{"name":"PIN por correo","type":"onetimepin","config":{}}' | j 'print(d["result"]["id"])')
echo "1) IdP PIN por correo: OK"
# 2) Inscripción de dispositivos (aplicación Access de tipo warp) limitada a los correos
INC=$(python3 -c 'import json,sys;print(json.dumps([{"email":{"email":e}} for e in json.loads(sys.argv[1])]))' "$EMAILS_JSON")
BODY=$(python3 -c 'import json,sys;print(json.dumps({"type":"warp","name":"Warp Login App","allowed_idps":[sys.argv[1]],"session_duration":"24h","policies":[{"name":"Equipo TI autorizado","decision":"allow","include":json.loads(sys.argv[2])}]}))' "$IDP" "$INC")
APP=$(call GET access/apps | j 'print(next((a["id"] for a in d["result"] if a.get("type")=="warp"),""))')
if [ -z "$APP" ]; then call POST access/apps "$BODY" >/dev/null; else call PUT "access/apps/$APP" "$BODY" >/dev/null; fi
echo "2) Inscripción WARP limitada a $(echo "$EMAILS_JSON" | j 'print(len(d))') correos: OK"
# 3) Proxy de Gateway (necesario para políticas de red por identidad)
call PATCH devices/settings '{"gateway_proxy_enabled":true,"gateway_udp_proxy_enabled":true}' >/dev/null && echo "3) Proxy TCP/UDP de Gateway: OK"
# 4) Split tunnel: quitar 10.0.0.0/8 de las exclusiones del perfil por defecto
EX=$(call GET devices/policy/exclude | j 'print(json.dumps([{k:v for k,v in e.items() if k in ("address","host","description")} for e in d["result"] if e.get("address")!="10.0.0.0/8"]))')
call PUT devices/policy/exclude "$EX" >/dev/null && echo "4) Split tunnel: 10.0.0.0/8 enrutado por WARP: OK"
# 5) Políticas de Gateway (reemplaza las que empiezan por "ACC ")
for id in $(call GET gateway/rules | j 'print(" ".join(r["id"] for r in d["result"] if r["name"].startswith("ACC ")))'); do call DELETE "gateway/rules/$id" >/dev/null; done
IDENT=$(python3 -c 'import json,sys;e=json.loads(sys.argv[1]);print("identity.email in {"+" ".join(json.dumps(x) for x in e)+"}")' "$EMAILS_JSON")
rule() { call POST gateway/rules "$1" >/dev/null && echo "5) Gateway: $(echo "$1" | j 'print(d["name"])')"; }
rule '{"name":"ACC DNS lam.evervc.dev interno","action":"override","filters":["dns"],"enabled":true,"precedence":100,"traffic":"any(dns.domains[*] == \"lam.evervc.dev\")","rule_settings":{"override_ips":["10.10.30.10"]}}'
rule "$(python3 -c 'import json,sys;print(json.dumps({"name":"ACC permitir equipo TI: LAM y escritorios","action":"allow","filters":["l4"],"enabled":True,"precedence":200,"traffic":"(net.dst.ip == 10.10.30.10 and net.dst.port == 443) or (net.dst.ip == 10.10.20.40 and net.dst.port == 3389)","identity":sys.argv[1]}))' "$IDENT")"
rule '{"name":"ACC bloquear resto de la red del laboratorio","action":"block","filters":["l4"],"enabled":true,"precedence":300,"traffic":"net.dst.ip in {10.10.0.0/16 10.20.0.0/16}"}'
# 6) Cloudflare Access delante de monitor.evervc.dev (Zabbix): solo WARP_EMAILS con PIN por correo (+ login propio de Zabbix)
MBODY=$(python3 -c 'import json,sys;print(json.dumps({"type":"self_hosted","name":"ACC Monitoreo (Zabbix)","domain":"monitor."+sys.argv[3],"allowed_idps":[sys.argv[1]],"auto_redirect_to_identity":True,"session_duration":"8h","app_launcher_visible":True,"policies":[{"name":"Equipo TI","decision":"allow","include":[{"email":{"email":e}} for e in json.loads(sys.argv[2])]}]}))' "$IDP" "$EMAILS_JSON" "$CF_ZONE")
MAPP=$(call GET access/apps | j 'print(next((a["id"] for a in d["result"] if a.get("name")=="ACC Monitoreo (Zabbix)"),""))')
if [ -z "$MAPP" ]; then call POST access/apps "$MBODY" >/dev/null; else call PUT "access/apps/$MAPP" "$MBODY" >/dev/null; fi
echo "6) Access monitor.$CF_ZONE: solo equipo TI (PIN por correo): OK"
