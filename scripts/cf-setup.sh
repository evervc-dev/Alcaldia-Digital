#!/bin/bash
# Cloudflare: túneles acc-site-a / acc-site-b (gestionados en remoto), ingress y DNS. Idempotente.
# Tokens e IDs de túnel -> .env (CF_TUNNEL_TOKEN_A/B, CF_TUNNEL_ID_A/B). Nunca se imprimen.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
API=https://api.cloudflare.com/client/v4; H=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
HOSTS="${CF_HOSTS:-portal archivo auth}"
py() { python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }
setenv() { grep -q "^$1=" .env && sed -i "s|^$1=.*|$1=$2|" .env || echo "$1=$2" >> .env; }
ZID=$(curl -fsS "${H[@]}" "$API/zones?name=$CF_ZONE" | py 'print(d["result"][0]["id"])')
tunnel() { # nombre ip_nginx sufijo
  local id; id=$(curl -fsS "${H[@]}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=$1&is_deleted=false" | py 'r=d["result"]; print(r[0]["id"] if r else "")')
  if [ -z "$id" ]; then
    id=$(curl -fsS "${H[@]}" -X POST "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel" -d "{\"name\":\"$1\",\"config_src\":\"cloudflare\"}" | py 'print(d["result"]["id"])')
    echo "túnel $1 creado"
  else echo "túnel $1 ya existía"; fi
  setenv "CF_TUNNEL_ID_$3" "$id"
  setenv "CF_TUNNEL_TOKEN_$3" "$(curl -fsS "${H[@]}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$id/token" | py 'print(d["result"])')"
  local ing; ing=$(python3 -c "
import json,sys
hs='$HOSTS'.split(); z='$CF_ZONE'
r=[{'hostname':f'{h}.{z}','service':'http://$2:80','originRequest':{'httpHostHeader':f'{h}.{z}'}} for h in hs]
r.append({'service':'http_status:404'}); print(json.dumps({'config':{'ingress':r}}))")
  curl -fsS "${H[@]}" -X PUT "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$id/configurations" -d "$ing" >/dev/null && echo "  ingress $1: $HOSTS -> $2:80"
}
tunnel acc-site-a 10.10.30.10 A
tunnel acc-site-b 10.20.30.10 B
set -a; . ./.env; set +a
for h in $HOSTS; do   # DNS -> túnel del Site A (el DR cambia a B con dr-dns-switch.sh)
  name="$h.$CF_ZONE"; body="{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$CF_TUNNEL_ID_A.cfargotunnel.com\",\"proxied\":true,\"ttl\":1,\"comment\":\"ACC Alcaldia Digital\"}"
  rid=$(curl -fsS "${H[@]}" "$API/zones/$ZID/dns_records?name=$name" | py 'r=d["result"]; print(r[0]["id"] if r else "")')
  if [ -n "$rid" ]; then curl -fsS "${H[@]}" -X PUT "$API/zones/$ZID/dns_records/$rid" -d "$body" >/dev/null; else curl -fsS "${H[@]}" -X POST "$API/zones/$ZID/dns_records" -d "$body" >/dev/null; fi
  echo "  DNS $name -> túnel A"
done
