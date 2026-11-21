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
