#!/bin/bash
# El token del túnel vive en /etc/acc/tunnel.token (volumen persistente; se escribe desde .env, nunca en git)
# T2 (F10): al conmutar de WAN el FW borra los estados NAT y las conexiones TCP del túnel quedan "zombis"
# (cloudflared se cree conectado, Cloudflare responde 530). Linux tardaría ~15 min en darlas por muertas:
# se acorta para que cloudflared reconecte por la nueva WAN en segundos.
# Además QUIC (no HTTP/2): con HTTP/2 el keepalive TCP lo fija Go (15 s + 9x15 s = 150 s de corte medido en T2);
# QUIC detecta la pérdida en pocos segundos y reconecta por la WAN que quede.
sysctl -qw net.ipv4.tcp_retries2=5 net.ipv4.tcp_keepalive_time=15 net.ipv4.tcp_keepalive_intvl=5 net.ipv4.tcp_keepalive_probes=3 2>/dev/null
if [ -s /etc/acc/tunnel.token ]; then
  ( while true; do cloudflared tunnel --no-autoupdate --protocol quic run --token "$(cat /etc/acc/tunnel.token)" >> /var/log/cloudflared.log 2>&1; sleep 5; done ) &
  echo "[acc] cloudflared iniciado"
else
  echo "[acc] falta /etc/acc/tunnel.token"
fi
exec /bin/bash -l
