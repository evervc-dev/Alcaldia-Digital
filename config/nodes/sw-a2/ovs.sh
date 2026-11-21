#!/bin/sh
# sw-a2 — núcleo del Site A (camino de energía B). Idempotente: se puede re-ejecutar.
# eth1 = trunk al firewall; eth14+eth15 = LACP "isl" hacia el otro switch; eth3.. = acceso
VLANS=10,20,30,40,50,60
ovs-vsctl --if-exists del-port br0 eth14 -- --if-exists del-port br0 eth15
ovs-vsctl --may-exist add-bond br0 isl eth14 eth15 lacp=active other_config:lacp-time=fast bond_mode=balance-slb
ovs-vsctl set port isl trunks=$VLANS
ovs-vsctl set port eth1 trunks=$VLANS
# Puertos de acceso (ver topology/topologia.md)
ovs-vsctl set port eth3 tag=40          # adm-pc (ADMINISTRACION)
ovs-vsctl set port eth4 tag=20          # dc1 (SERVIDORES)
# Puertos libres -> VLAN de aparcamiento 999 (sin gateway)
for p in eth0 eth2 eth5 eth6 eth7 eth8 eth9 eth10 eth11 eth12 eth13; do
  ovs-vsctl --if-exists set port $p tag=999
done
# Interfaz de gestión en VLAN 10
ovs-vsctl --may-exist add-port br0 mgmt tag=10 -- set interface mgmt type=internal
