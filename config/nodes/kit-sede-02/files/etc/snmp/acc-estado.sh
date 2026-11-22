#!/bin/sh
# Métricas del kit para SNMP extend (Zabbix): tunel <nombre> -> 1/0 ; ospf -> nº de vecinos Full
case "$1" in
  tunel) swanctl --list-sas --ike "$2" 2>/dev/null | grep -q ESTABLISHED && echo 1 || echo 0 ;;
  ospf)  vtysh -c 'show ip ospf neighbor' 2>/dev/null | grep -c Full ;;
esac
