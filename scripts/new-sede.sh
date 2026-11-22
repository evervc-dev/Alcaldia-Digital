#!/bin/bash
# Kit de sede replicable (equivalente al FortiGate 40F del diseño). Genera config/nodes/kit-sede-NN/ y las PC.
# Uso: new-sede.sh <N>      (N = número de sede, 1..255)
# Para una sede nueva además: añadir su IP pública del pool CGNAT a SEDES_PUB (config/opnsense/wan-ab.inc.php)
# y a la regla snat del ISP (config/nodes/ispX/main.nft); crear su OU (ad-ou-delegacion.sh N) y sus nodos en GNS3.
set -euo pipefail; cd "$(dirname "$0")/.."
N=$((10#$1)); NN=$(printf %02d $N); K=config/nodes/kit-sede-$NN; mkdir -p $K
cat > $K/interfaces <<EOI
# kit-sede-$NN: WAN detrás del CGNAT del ISP (100.64.$N.2/30) + LAN 10.100.$N.0/24 + 3 túneles XFRM (route-based)
auto eth0
iface eth0 inet static
	address 100.64.$N.2
	netmask 255.255.255.252
	gateway 100.64.$N.1
	up printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
auto eth1
iface eth1 inet static
	address 10.100.$N.1
	netmask 255.255.255.0
	up /sbin/ip route add blackhole 10.0.0.0/8 metric 250 2>/dev/null || true   # sin túnel, la red del CD NUNCA sale por Internet
EOI
for t in "a1 1 2 Site A por WAN1 (coste 10)" "a2 2 6 Site A por WAN2 (coste 20)" "b 3 10 Site B (coste 100)"; do set -- $t; cat >> $K/interfaces <<EOI
# vti-$1: ${*:4}
auto vti-$1
iface vti-$1 inet static
	pre-up /sbin/ip link add vti-$1 type xfrm dev eth0 if_id $2 2>/dev/null || true
	pre-up /sbin/ip link set vti-$1 mtu 1400   # igual que la VTI de OPNsense (si no, OSPF queda en ExStart)
	address 172.16.$N.$3
	netmask 255.255.255.252
EOI
done
cat > $K/swanctl.conf <<EOS
# kit-sede-$NN: 3 túneles IKEv2 SALIENTES (la sede está tras CGNAT: NAT-T). Identidad: FQDN. PSK en acc-secrets.conf (no en git).
connections {
EOS
for t in "a-wan1 203.0.113.4 1" "a-wan2 198.51.100.4 2" "b 203.0.113.10 3"; do set -- $t; cat >> $K/swanctl.conf <<EOS
    $1 {
        version = 2
        remote_addrs = $2
        mobike = no
        keyingtries = 0
        dpd_delay = 5s
        local { auth = psk
                id = kit-sede-$NN.alcaldia.lab }
        remote { auth = psk
                 id = $2 }
        children {
            $1 { local_ts = 0.0.0.0/0
                 remote_ts = 0.0.0.0/0
                 if_id_in = $3
                 if_id_out = $3
                 start_action = start
                 dpd_action = restart
                 close_action = start }
        }
    }
EOS
done
cat >> $K/swanctl.conf <<EOS
}
include /etc/swanctl/acc-secrets.conf
EOS
cat > $K/frr.conf <<EOF2
frr defaults traditional
hostname kit-sede-$NN
log syslog informational
!
interface vti-a1
 ip ospf network point-to-point
 ip ospf mtu-ignore
 ip ospf cost 10
 ip ospf hello-interval 2
 ip ospf dead-interval 8
exit
interface vti-a2
 ip ospf network point-to-point
 ip ospf mtu-ignore
 ip ospf cost 20
 ip ospf hello-interval 2
 ip ospf dead-interval 8
exit
interface vti-b
 ip ospf network point-to-point
 ip ospf mtu-ignore
 ip ospf cost 100
 ip ospf hello-interval 2
 ip ospf dead-interval 8
exit
!
router ospf
 ospf router-id 10.100.$N.1
 passive-interface eth1
 network 172.16.$N.0/28 area 0
 network 10.100.$N.0/24 area 0
exit
!
EOF2
cat > $K/main.nft <<EOF3
# kit-sede-$NN: Internet sale por el ISP local (NAT); la red del centro de datos (10/8) va por los túneles sin NAT
flush ruleset
table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    oifname "eth0" ip daddr != 10.0.0.0/8 masquerade
  }
}
table ip filter {
  chain forward {
    type filter hook forward priority 0; policy accept;
    tcp flags syn tcp option maxseg size set rt mtu    # MSS ajustado a la MTU de los túneles
    # T5 (F10): la sede no necesita NADA de GESTION, ADMIN, DMZ, RESPALDO ni de las IP de los firewalls (su DNS es dc1/dc2).
    # pf de OPNsense no filtra lo que llega por la VTI con destino al propio firewall -> se corta aquí (OSPF del kit no pasa por forward).
    ip daddr { 10.10.10.0/24, 10.10.30.0/24, 10.10.40.0/24, 10.10.60.0/24, 10.20.10.0/24, 10.20.30.0/24, 10.20.40.0/24, 10.20.60.0/24, 172.16.0.0/16, 10.10.20.1-10.10.20.3, 10.10.50.1-10.10.50.3, 10.20.20.1 } counter drop
  }
}
EOF3
cat > $K/dnsmasq.conf <<EOF4
# kit-sede-$NN: DHCP de la LAN de la sede (sin DNS local: los clientes usan dc1/dc2 por el túnel)
interface=eth1
bind-interfaces
port=0
dhcp-range=10.100.$N.100,10.100.$N.199,255.255.255.0,12h
dhcp-option=option:router,10.100.$N.1
dhcp-option=option:dns-server,10.10.20.10,10.20.20.10
dhcp-option=option:domain-search,ad.alcaldia.lab
dhcp-authoritative
EOF4
# SNMP de solo lectura para Zabbix (F8): la comunidad va en acc-community.conf (desde .env, lo instala sede-setup.sh)
cat > $K/snmpd.conf <<EOF5
# acc: SNMP del kit de la sede $NN; solo lectura y solo desde zbx-server (10.10.20.30)
agentaddress udp:161
includeFile /etc/snmp/acc-community.conf
sysLocation Sede $NN (kit-sede-$NN)
sysContact mesa@alcaldia.lab
# estado de cada túnel IPsec (1 = ESTABLISHED) y vecinos OSPF en Full
extend tunel-a-wan1 /etc/snmp/acc-estado.sh tunel a-wan1
extend tunel-a-wan2 /etc/snmp/acc-estado.sh tunel a-wan2
extend tunel-b /etc/snmp/acc-estado.sh tunel b
extend ospf-full /etc/snmp/acc-estado.sh ospf
EOF5
mkdir -p $K/files/etc/snmp
cat > $K/files/etc/snmp/acc-estado.sh <<'EOF6'
#!/bin/sh
# Métricas del kit para SNMP extend (Zabbix): tunel <nombre> -> 1/0 ; ospf -> nº de vecinos Full
case "$1" in
  tunel) swanctl --list-sas --ike "$2" 2>/dev/null | grep -q ESTABLISHED && echo 1 || echo 0 ;;
  ospf)  vtysh -c 'show ip ospf neighbor' 2>/dev/null | grep -c Full ;;
esac
EOF6
for p in a b; do mkdir -p config/nodes/pc-$NN-$p; printf '# pc-%s-%s: PC de funcionario de la sede %s (DHCP del kit)\nauto eth0\niface eth0 inet dhcp\n' $NN $p $NN > config/nodes/pc-$NN-$p/interfaces; done
echo "kit-sede-$NN generado en $K (+ pc-$NN-a, pc-$NN-b)"
