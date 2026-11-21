#!/bin/sh
# sw-b2 — Site B (Tier I), expansión. eth15 = enlace a sw-b1; eth3.. = acceso
VLANS=10,20,30,40,60
ovs-vsctl set port eth1 tag=999
ovs-vsctl set port eth15 trunks=$VLANS
ovs-vsctl set port eth3 tag=999
for p in eth0 eth2 eth4 eth5 eth6 eth7 eth8 eth9 eth10 eth11 eth12 eth13 eth14; do ovs-vsctl --if-exists set port $p tag=999; done
ovs-vsctl --may-exist add-port br0 mgmt tag=10 -- set interface mgmt type=internal
