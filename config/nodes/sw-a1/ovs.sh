#!/bin/sh
# sw-a1 — núcleo del Site A (camino de energía A). Idempotente: se puede re-ejecutar.
# eth1 = trunk al firewall; eth14+eth15 = LACP "isl" hacia el otro switch; eth3.. = acceso
VLANS=10,20,30,40,50,60
# 24 puertos (ampliado en F5): los nuevos se añaden al bridge (init.sh solo los añade en el primer arranque)
for i in $(seq 0 23); do ovs-vsctl --may-exist add-port br0 eth$i 2>/dev/null; done
ovs-vsctl --if-exists del-port br0 eth14 -- --if-exists del-port br0 eth15
ovs-vsctl --may-exist add-bond br0 isl eth14 eth15 lacp=active other_config:lacp-time=fast bond_mode=balance-slb
ovs-vsctl set port isl trunks=$VLANS
ovs-vsctl set port eth1 trunks=$VLANS
# Puertos de acceso (ver topology/topologia.md)
ovs-vsctl set port eth3 tag=40          # adm-pc (ADMINISTRACION)
ovs-vsctl set port eth4 tag=20          # dc1 (SERVIDORES)
ovs-vsctl set port eth6 tag=60          # nas-a (RESPALDO)
ovs-vsctl set port eth7 tag=20          # ts1 (SERVIDORES)
ovs-vsctl set port eth5 tag=50          # usr-pc (USUARIOS)
ovs-vsctl set port eth20 tag=30        # nginx-dmz (DMZ) (eth8 ocupado por enlace fantasma)
ovs-vsctl set port eth9 tag=30    # cloudflared-a (DMZ)
ovs-vsctl set port eth19 tag=20        # authelia (eth10 quedó ocupado por un enlace fantasma de GNS3)
ovs-vsctl set port eth11 tag=20   # gate (horario)
ovs-vsctl set port eth12 tag=20   # portal
ovs-vsctl set port eth13 tag=20   # portal-db
ovs-vsctl set port eth16 tag=20   # archivo
ovs-vsctl set port eth17 tag=20   # mailpit
ovs-vsctl set port eth18 tag=50   # pc-gui (USUARIOS)
ovs-vsctl set port eth21 tag=20        # lam (gestión de identidades)
ovs-vsctl set port eth22 tag=20   # zbx-db (monitoreo)
ovs-vsctl set port eth23 tag=20   # zbx-server (monitoreo)
ovs-vsctl set port eth2 tag=20    # zbx-web (monitoreo)
# Puertos libres -> VLAN de aparcamiento 999 (sin gateway)
for p in eth0 eth10 eth8; do
  ovs-vsctl --if-exists set port $p tag=999
done
# Interfaz de gestión en VLAN 10
ovs-vsctl --may-exist add-port br0 mgmt tag=10 -- set interface mgmt type=internal
