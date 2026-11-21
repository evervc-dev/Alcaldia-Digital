#!/usr/bin/env python3
"""Genera config/nodes/<nodo>/interfaces.
  gen-if.py bond   <nodo> <ip> <gw> "<descripción>" [dns1,dns2]   -> bond0 active-backup A/B con monitoreo ARP al gw
  gen-if.py single <nodo> <ip> <gw> "<descripción>" [dns1,dns2]   -> eth0 estático (Tier I / un camino)"""
import sys, os
mode, node, ip, gw, desc = sys.argv[1:6]
dns = (sys.argv[6] if len(sys.argv) > 6 else "10.10.20.10,10.20.20.10").split(",")
res = "search ad.alcaldia.lab\\n" + "".join(f"nameserver {d}\\n" for d in dns)
if mode == "bond":
    body = f"""# {node}: {desc}
# bond0 active-backup: eth0 -> sw-a1 (camino A), eth1 -> sw-a2 (camino B); monitoreo ARP al gateway (VIP)
auto bond0
iface bond0 inet static
	pre-up ip link add bond0 type bond 2>/dev/null || true
	pre-up echo active-backup > /sys/class/net/bond0/bonding/mode; echo 200 > /sys/class/net/bond0/bonding/arp_interval; echo +{gw} > /sys/class/net/bond0/bonding/arp_ip_target
	pre-up ip link set eth0 down; ip link set eth1 down; echo +eth0 > /sys/class/net/bond0/bonding/slaves; echo +eth1 > /sys/class/net/bond0/bonding/slaves
	address {ip}
	netmask 255.255.255.0
	gateway {gw}
	up printf '{res}' > /etc/resolv.conf
"""
else:
    body = f"""# {node}: {desc}
auto eth0
iface eth0 inet static
	address {ip}
	netmask 255.255.255.0
	gateway {gw}
	up printf '{res}' > /etc/resolv.conf
"""
os.makedirs(f"config/nodes/{node}", exist_ok=True)
open(f"config/nodes/{node}/interfaces", "w").write(body)
print(f"config/nodes/{node}/interfaces ({mode} {ip})")
