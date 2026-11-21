#!/bin/bash
# Conmutación de DNS para DR (Fase 5, P-A): apunta portal/archivo/auth.evervc.dev al túnel del sitio indicado.
# Uso: dr-dns-switch.sh B   (activar Site B)   |   dr-dns-switch.sh A   (retorno al Site A)
# Proxied + TTL automático: Cloudflare aplica el cambio en segundos (no depende del TTL de los clientes).
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
S=${1:?uso: dr-dns-switch.sh A|B}; T="CF_TUNNEL_ID_$S"; TID=${!T}
API=https://api.cloudflare.com/client/v4; H=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
ZID=$(curl -fsS "${H[@]}" "$API/zones?name=$CF_ZONE" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"][0]["id"])')
for h in ${CF_HOSTS:-portal archivo auth}; do
  n="$h.$CF_ZONE"; rid=$(curl -fsS "${H[@]}" "$API/zones/$ZID/dns_records?name=$n" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"][0]["id"])')
  curl -fsS "${H[@]}" -X PUT "$API/zones/$ZID/dns_records/$rid" -d "{\"type\":\"CNAME\",\"name\":\"$n\",\"content\":\"$TID.cfargotunnel.com\",\"proxied\":true,\"ttl\":1,\"comment\":\"ACC DR -> Site $S $(date -Is)\"}" >/dev/null
  echo "$(date +%T) $n -> túnel Site $S"
done
