#!/bin/bash
# Servicios propios del kit: IPsec (strongSwan/swanctl) y DHCP/DNS local (dnsmasq)
# cada (re)arranque de charon vuelve a cargar conexiones y secretos (si no, el kit queda sin túneles)
( while true; do ( sleep 3; swanctl --load-all >/dev/null 2>&1 ) & /usr/lib/strongswan/charon >>/var/log/charon.log 2>&1; sleep 5; done ) &
sleep 2
swanctl --load-all >/dev/null 2>&1 || echo "[acc] swanctl: sin configuración todavía"
ls /etc/dnsmasq.d/*.conf >/dev/null 2>&1 && dnsmasq --conf-dir=/etc/dnsmasq.d,*.conf
true
