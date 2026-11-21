#!/bin/bash
# Arranque idempotente: solo siembra configuración si el volumen está vacío.
sysctl -qw net.ipv4.ip_forward=1 2>/dev/null || true
[ -f /etc/frr/daemons ] || cp -a /opt/acc/defaults/frr/. /etc/frr/
chown -R frr:frr /etc/frr 2>/dev/null || true
for f in /etc/nftables.d/*.nft; do [ -f "$f" ] && nft -f "$f"; done
[ -f /etc/snmp/snmpd.conf ] && snmpd -Lsd -c /etc/snmp/snmpd.conf
/usr/lib/frr/frrinit.sh start >/dev/null 2>&1 || echo "[acc] aviso: FRR no arrancó"
[ -x /opt/acc/extra.sh ] && /opt/acc/extra.sh
echo "[acc] $(hostname) listo"
exec /bin/bash -l
