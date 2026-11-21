#!/bin/bash
# Estructura de OU por sede + grupo gestores-identidad con delegación MÍNIMA (PLAN §12). Idempotente.
#  - OU=Funcionarios,<base>  y  OU=Sede-0N,OU=Funcionarios
#  - gestores-identidad: crear/eliminar usuarios y control total SOBRE USUARIOS en OU=Funcionarios (heredable a las sedes)
#                        + modificar miembros SOLO del grupo 'funcionarios' (no 'acceso-24h' ni grupos privilegiados)
# Uso: ad-ou-delegacion.sh [N_SEDES=3]
set -euo pipefail; cd "$(dirname "$0")/.."
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
DC="GNS3.dc1.$PID"; BASE="DC=ad,DC=alcaldia,DC=lab"; N=${1:-3}
dcx() { docker exec "$DC" sh -c "$1"; }
USER_CLASS=bf967aba-0de6-11d0-a285-00aa003049e2     # objeto user
MEMBER_ATTR=bf9679c0-0de6-11d0-a285-00aa003049e2    # atributo member
dcx "samba-tool ou create 'OU=Funcionarios,$BASE' --description='Funcionarios de las sedes distritales' >/dev/null 2>&1 || true"
for i in $(seq 1 $N | xargs printf "%02d "); do dcx "samba-tool ou create 'OU=Sede-$i,OU=Funcionarios,$BASE' --description='Sede distrital $i' >/dev/null 2>&1 || true"; done
echo "OU: Funcionarios + Sede-01..Sede-$(printf %02d $N)"
dcx "samba-tool group show gestores-identidad >/dev/null 2>&1 || samba-tool group add gestores-identidad --description='TI: gestión de cuentas de funcionarios (delegación limitada)' >/dev/null"
SID=$(dcx "samba-tool group show gestores-identidad --attributes=objectSid | sed -n 's/^objectSid: //p'")
echo "grupo gestores-identidad: $SID"
dcx "samba-tool dsacl set --objectdn='OU=Funcionarios,$BASE' --sddl='(OA;CI;CCDC;$USER_CLASS;;$SID)' >/dev/null && samba-tool dsacl set --objectdn='OU=Funcionarios,$BASE' --sddl='(OA;CIIO;GA;;$USER_CLASS;$SID)' >/dev/null"
dcx "samba-tool dsacl set --objectdn='CN=funcionarios,CN=Users,$BASE' --sddl='(OA;;WP;$MEMBER_ATTR;;$SID)' >/dev/null"
echo "delegación aplicada: OU=Funcionarios (usuarios) + miembros de 'funcionarios'"
dcx "samba-tool group addmembers gestores-identidad tecnico.soporte >/dev/null 2>&1 || true"; echo "tecnico.soporte -> gestores-identidad"
dcx "samba-tool user move ana.funcionaria 'OU=Sede-01,OU=Funcionarios,$BASE' >/dev/null 2>&1 || true"; echo "ana.funcionaria -> OU=Sede-01"
