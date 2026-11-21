#!/bin/sh
# sw-b1 — Site B (Tier I). eth1 = trunk a fw-b; eth15 = enlace a sw-b2; eth3.. = acceso
VLANS=10,20,30,40,60
ovs-vsctl set port eth1 trunks=$VLANS
ovs-vsctl set port eth15 trunks=$VLANS
ovs-vsctl set port eth3 tag=40          # adm-pc-b (ADMINISTRACION B)
ovs-vsctl set port eth4 tag=20          # dc2 (SERVIDORES B)
for p in eth0 eth2 eth5 eth6 eth7 eth8 eth9 eth10 eth11 eth12 eth13 eth14; do ovs-vsctl --if-exists set port $p tag=999; done
ovs-vsctl --may-exist add-port br0 mgmt tag=10 -- set interface mgmt type=internal
