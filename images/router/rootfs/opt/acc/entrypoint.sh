#!/bin/bash
# Arranque idempotente: solo siembra configuración si el volumen está vacío.
sysctl -qw net.ipv4.ip_forward=1 2>/dev/null || true
cp -an /opt/acc/defaults/frr/. /etc/frr/   # siembra sin sobrescribir
sed -i "s/^bgpd=no/bgpd=yes/; s/^ospfd=no/ospfd=yes/" /etc/frr/daemons   # BGP y OSPF siempre activos
chown -R frr:frr /etc/frr 2>/dev/null || true
for f in /etc/nftables.d/*.nft; do [ -f "$f" ] && nft -f "$f"; done
grep -qs "^# acc" /etc/snmp/snmpd.conf && snmpd -Lsd -c /etc/snmp/snmpd.conf   # solo con config propia (F8)
/usr/lib/frr/frrinit.sh start >/dev/null 2>&1 || echo "[acc] aviso: FRR no arrancó"
[ -x /opt/acc/extra.sh ] && /opt/acc/extra.sh
echo "[acc] $(hostname) listo"
exec /bin/bash -l
