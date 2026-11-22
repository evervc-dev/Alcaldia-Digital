#!/bin/bash
# Rellena con valores aleatorios SOLO las variables vacías del .env (no muestra los valores).
set -euo pipefail; cd "$(dirname "$0")/.."
rnd() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-"$1"; }
fill() { # var valor
  if grep -qE "^$1=$" .env; then sed -i "s|^$1=$|$1=$2|" .env; echo "$1: generado";
  elif ! grep -qE "^$1=" .env; then echo "$1=$2" >> .env; echo "$1: generado"; else echo "$1: ya tenía valor"; fi
}
fill SAMBA_ADMIN_PASS "Acc-$(rnd 14)-9x"       # complejidad AD: mayúscula, minúscula, dígito, símbolo
fill PORTAL_DB_PASS "$(rnd 24)"
fill ZABBIX_DB_PASS "$(rnd 24)"
fill AUTHELIA_JWT_SECRET "$(rnd 48)"
fill AUTHELIA_SESSION_SECRET "$(rnd 48)"
fill AUTHELIA_STORAGE_KEY "$(rnd 48)"
fill SVC_LDAP_PASS "Svc-$(rnd 16)-7k"            # cuenta de servicio LDAP (solo lectura)
fill LAB_USER_PASS "Demo-$(rnd 10)-4q"            # contraseña común de los usuarios de demostración
fill MINIO_ROOT_PASS "$(rnd 28)"
fill LAM_MASTER_PASS "$(rnd 24)"           # contraseña maestra de configuración de LAM
fill IPSEC_PSK_SEDES "$(rnd 40)"            # PSK de los túneles de las sedes
fill ZABBIX_ADMIN_PASS "Zbx-$(rnd 16)-3m"       # usuario Admin del frontend de Zabbix
fill RESTIC_PASSWORD "$(rnd 40)"          # cifrado del repositorio restic (¡sin ella no se restaura nada!)
fill RESTIC_S3_KEY "$(rnd 32)"            # usuario MinIO "restic" (escribe, no borra versiones)
fill RESTIC_RO_KEY "$(rnd 32)"            # usuario MinIO "restic-lectura" (Zabbix)
fill ZBX_SNMP_COMMUNITY "acc$(rnd 20)"          # comunidad SNMP de solo lectura (solo zbx-server)
fill GLPI_DB_PASS "$(rnd 24)"              # MariaDB: usuario glpi
fill GLPI_DB_ROOT_PASS "$(rnd 24)"         # MariaDB: root (solo local en glpi-db)
fill GLPI_ADMIN_PASS "Glpi-$(rnd 16)-5w"   # cuenta local de emergencia 'glpi' (super-admin) de GLPI
fill GLPI_ZABBIX_PASS "Zbx-$(rnd 20)-8t"     # usuario GLPI "zabbix" (API): Zabbix abre/cierra tickets
