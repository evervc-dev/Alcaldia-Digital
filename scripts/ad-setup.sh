#!/bin/bash
# Grupos, cuenta de servicio, usuarios de demostración y horario (logonHours) en el AD. Idempotente.
# Horario de 'funcionarios': lun-vie 8:00-16:00 hora de El Salvador (UTC-6) = 14:00-22:00 UTC.
# Uso: ad-setup.sh                    -> base completa
#      ad-setup.sh usuario <u> <grupo> "<Nombre Apellido>"   -> alta/actualización de un usuario
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
DC="GNS3.dc1.$PID"
dcx() { docker exec -e AP="$LAB_USER_PASS" -e SP="$SVC_LDAP_PASS" "$DC" sh -c "$1"; }
# 21 bytes = 168 horas desde domingo 00:00 UTC; bit menos significativo primero
LH=$(python3 -c '
b=bytearray(21)
for d in range(1,6):
  for h in range(14,22):
    i=d*24+h; b[i//8]|=1<<(i%8)
import base64; print(base64.b64encode(bytes(b)).decode())')
horario() { # usuario
  dcx "dn=\$(ldbsearch -H /var/lib/samba/private/sam.ldb \"(sAMAccountName=$1)\" dn | sed -n 's/^dn: //p'); printf 'dn: %s\nchangetype: modify\nreplace: logonHours\nlogonHours:: %s\n' \"\$dn\" '$LH' | ldbmodify -H /var/lib/samba/private/sam.ldb >/dev/null && echo '  horario lun-vie 8-16 -> $1'"
}
usuario() { # usuario grupo "Nombre Apellido"
  read -r gn sn <<<"$3"
  dcx "samba-tool user show $1 >/dev/null 2>&1 || samba-tool user create $1 \"\$AP\" --given-name='$gn' --surname='$sn' >/dev/null; samba-tool user setexpiry $1 --noexpiry >/dev/null; samba-tool group addmembers $2 $1 >/dev/null 2>&1 || true; echo '  usuario $1 ($2)'"
  [ "$2" = funcionarios ] && horario "$1" || true
}
if [ "${1:-}" = usuario ]; then usuario "$2" "$3" "$4"; exit; fi
for g in funcionarios acceso-24h nas-admins; do dcx "samba-tool group show $g >/dev/null 2>&1 || samba-tool group add $g >/dev/null; echo '  grupo $g'"; done
dcx "samba-tool user show svc-lectura >/dev/null 2>&1 || samba-tool user create svc-lectura \"\$SP\" --description='Cuenta de servicio LDAP (solo lectura)' >/dev/null; samba-tool user setexpiry svc-lectura --noexpiry >/dev/null; echo '  cuenta de servicio svc-lectura'"
usuario ana.funcionaria funcionarios "Ana Funcionaria"
usuario tecnico.soporte acceso-24h "Tecnico Soporte"
usuario admin.dc acceso-24h "Admin DC"
dcx "samba-tool group addmembers 'Domain Admins' admin.dc >/dev/null 2>&1; samba-tool group addmembers nas-admins admin.dc >/dev/null 2>&1; echo '  admin.dc -> Domain Admins, nas-admins'"
