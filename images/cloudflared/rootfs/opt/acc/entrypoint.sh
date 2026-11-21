#!/bin/bash
# El token del túnel vive en /etc/acc/tunnel.token (volumen persistente; se escribe desde .env, nunca en git)
if [ -s /etc/acc/tunnel.token ]; then
  cloudflared tunnel --no-autoupdate --protocol http2 run --token "$(cat /etc/acc/tunnel.token)" > /var/log/cloudflared.log 2>&1 &
  echo "[acc] cloudflared iniciado"
else
  echo "[acc] falta /etc/acc/tunnel.token"
fi
exec /bin/bash -l
