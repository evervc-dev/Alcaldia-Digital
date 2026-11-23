#!/bin/bash
# Crea en el AD las personas de un archivo PRIVADO (fuera de git) con secciones: # Administrador, # Equipo de Soporte, # Equipo de TI, # Funcionarios.
# Usuario = parte local del correo. Contraseña aleatoria, solo para cuentas NUEVAS, anotada en el mismo archivo (permisos 600). No la muestra.
# Uso: equipo-setup.sh <archivo.md>
set -euo pipefail; F=$(realpath "${1:?archivo}"); cd "$(dirname "$0")/.."
git ls-files --error-unmatch "$F" >/dev/null 2>&1 && { echo "el archivo está en git: no se escriben contraseñas"; exit 1; }
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename); chmod 600 "$F"
ad() { docker exec -i -e PW="${PW:-}" "GNS3.dc1.$PID" sh -c "$1" </dev/null; }
NUEVAS=$(mktemp); chmod 600 "$NUEVAS"; trap 'rm -f -- "$NUEVAS"' EXIT; SEC=""
while IFS= read -r l; do l=$(tr -d '\r' <<<"$l" | xargs || true)
  case "$l" in \#*) SEC=$(tr 'A-Z' 'a-z' <<<"${l##*\#}"); [[ $SEC == *"credenciales"* ]] && break; continue ;; *@*) ;; *) continue ;; esac
  M=$(tr 'A-Z' 'a-z' <<<"$l"); U=${M%%@*}; [[ $U =~ ^[a-z0-9._-]{1,20}$ && $M =~ ^[a-z0-9._-]+@[a-z0-9.-]+$ ]] || { echo "! correo no válido, se omite"; continue; }
  case "$SEC" in *admin*) R=rol-admin; OU=OU=TI,OU=Centro-Datos; G="Domain Admins,nas-admins,mesa-admins" ;; *soporte*) R=rol-soporte; OU=OU=Soporte,OU=Centro-Datos; G=mesa-tecnicos ;;
    *ti*) R=rol-ti; OU=OU=TI,OU=Centro-Datos; G="gestores-identidad,mesa-tecnicos" ;; *funcionario*) R=funcionarios; OU=OU=Sede-01,OU=Funcionarios; G="" ;; *) echo "! sección desconocida"; continue ;; esac
  if ad "samba-tool user show '$U' >/dev/null 2>&1"; then E="ya existía"
  else PW="Al-$(openssl rand -base64 24 | tr -d '/+=lIO0' | cut -c1-12)-$((RANDOM % 90 + 10))"
    ad "samba-tool user create '$U' \"\$PW\" --userou='$OU' --mail-address='$M' --given-name='$U' >/dev/null && samba-tool user setexpiry '$U' --noexpiry >/dev/null"; E=creado
    printf '| `%s` | %s | `%s` |\n' "$U" "$R" "$PW" >> "$NUEVAS"; unset PW; fi
  IFS=, read -ra GS <<<"$R${G:+,$G}"; for g in "${GS[@]}"; do ad "samba-tool group addmembers '$g' '$U' >/dev/null 2>&1 || true"; done; echo "  $U: $E ($R)"
done < "$F"
if [ -s "$NUEVAS" ]; then { printf '\n# Credenciales iniciales (%s, NO compartir ni subir a git)\n\n| Usuario | Rol | Contraseña inicial |\n|---|---|---|\n' "$(date +%F)"; cat "$NUEVAS"; } >> "$F"; echo "$(wc -l < "$NUEVAS") contraseñas anotadas en $F"; fi
