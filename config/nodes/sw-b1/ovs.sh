#!/bin/sh
# sw-b1 — Site B (Tier I). eth1 = trunk a fw-b; eth15 = enlace a sw-b2; eth3.. = acceso
VLANS=10,20,30,40,60
ovs-vsctl set port eth1 trunks=$VLANS
ovs-vsctl set port eth15 trunks=$VLANS
ovs-vsctl set port eth3 tag=40          # adm-pc-b (ADMINISTRACION B)
ovs-vsctl set port eth4 tag=20          # dc2 (SERVIDORES B)
ovs-vsctl set port eth5 tag=60          # nas-b (RESPALDO B)
ovs-vsctl set port eth6 tag=30    # nginx-dmz-b (DMZ B)
ovs-vsctl set port eth7 tag=30    # cloudflared-b (DMZ B)
ovs-vsctl set port eth8 tag=20    # portal-db-b
ovs-vsctl set port eth9 tag=20    # portal-b (espera)
ovs-vsctl set port eth10 tag=20   # archivo-b (espera)
ovs-vsctl set port eth11 tag=20   # authelia-b (espera)
ovs-vsctl set port eth12 tag=20   # gate-b (espera)
for p in eth0 eth2 eth13 eth14; do ovs-vsctl --if-exists set port $p tag=999; done
ovs-vsctl --may-exist add-port br0 mgmt tag=10 -- set interface mgmt type=internal
