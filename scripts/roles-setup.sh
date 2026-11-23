#!/bin/bash
# Roles del personal en el AD (4 niveles) y almacén de la política de acceso. Idempotente, no borra nada.
#  rol-admin    todo (miembro de Domain Admins)      rol-ti      infraestructura; crea empleados (gestores-identidad)
#  rol-soporte  mesa nivel 1; SOLO restablece contraseñas de empleados     funcionarios  empleados de las sedes
#  OU=Politica-Acceso: horarios y excepciones (objetos acc-*, JSON en «info»); solo svc-politica (gate) y Domain Admins escriben.
# Va en el AD porque se replica a dc2 y lo leen gate, ts1 y los puestos con su propia cuenta.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
docker exec -i -e AP="$LAB_USER_PASS" -e PP="$SVC_POLITICA_PASS" "GNS3.dc1.$PID" sh -s <<'SH'
set -e; B=DC=ad,DC=alcaldia,DC=lab
grupo() { samba-tool group show "$1" >/dev/null 2>&1 || samba-tool group add "$1" --description="$2" >/dev/null; }
ou() { samba-tool ou list --full-dn 2>/dev/null | grep -qix "$1,$B" || samba-tool ou create "$1,$B" >/dev/null; }
miembro() { samba-tool group addmembers "$1" "$2" >/dev/null 2>&1 || true; }
usuario() { samba-tool user show "$1" >/dev/null 2>&1 || samba-tool user create "$1" "$4" --userou="$2" --given-name="$3" --mail-address="$1@alcaldia.lab" >/dev/null
            samba-tool user setexpiry "$1" --noexpiry >/dev/null; }
sid() { samba-tool group show "$1" --attributes=objectSid | sed -n 's/^objectSid: //p'; }
usid() { samba-tool user show "$1" --attributes=objectSid | sed -n 's/^objectSid: //p'; }
acl() { samba-tool dsacl get --objectdn="$1" 2>/dev/null | grep -qF "$2" || samba-tool dsacl set --objectdn="$1" --sddl="$2" >/dev/null; }
grupo rol-admin "Administradores del centro de datos"; grupo rol-ti "TI: infraestructura (nivel 2)"; grupo rol-soporte "Soporte: mesa de servicio (nivel 1)"
ou OU=Centro-Datos; ou OU=TI,OU=Centro-Datos; ou OU=Soporte,OU=Centro-Datos; ou OU=Politica-Acceso
usuario ti.guardia OU=TI,OU=Centro-Datos "TI Guardia" "$AP"; usuario soporte.mesa OU=Soporte,OU=Centro-Datos "Soporte Mesa" "$AP"
usuario svc-politica CN=Users "Servicio politica" "$PP"; samba-tool user setpassword svc-politica --newpassword="$PP" >/dev/null 2>&1 || true
miembro rol-admin admin.dc; miembro rol-ti tecnico.soporte; miembro rol-ti ti.guardia; miembro rol-soporte soporte.mesa
miembro gestores-identidad ti.guardia; for u in ti.guardia soporte.mesa; do miembro mesa-tecnicos $u; done
P=$(usid svc-politica); S=$(sid rol-soporte); O=OU=Politica-Acceso,$B; F=OU=Funcionarios,$B; U=bf967aba-0de6-11d0-a285-00aa003049e2
acl "$O" "(OA;;CCDC;bf967a9c-0de6-11d0-a285-00aa003049e2;;$P)"                      # crear/borrar objetos group
acl "$O" "(OA;CIIO;GA;;bf967a9c-0de6-11d0-a285-00aa003049e2;$P)"                    # y control sobre ellos
acl "$F" "(OA;CIIO;CR;00299570-246d-11d0-a768-00aa006e0529;$U;$S)"                  # soporte: restablecer contraseña
acl "$F" "(OA;CIIO;RPWP;bf967a0a-0de6-11d0-a285-00aa003049e2;$U;$S)"                # ... pwdLastSet (cambio al entrar)
acl "$F" "(OA;CIIO;RPWP;28630ebf-41d5-11d1-a9c1-0000f80367c1;$U;$S)"                # ... lockoutTime (desbloquear)
for g in rol-admin rol-ti rol-soporte; do echo "$g: $(samba-tool group listmembers $g | tr '\n' ' ')"; done
SH
