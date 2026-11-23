#!/bin/bash
# Configura filebrowser (nodo "archivo") con el nodo DETENIDO: autenticación por cabecera Remote-User (Authelia)
# y carpeta personal automática /users/<usuario>. Usa un contenedor temporal (--rm) sobre el volumen del proyecto.
set -euo pipefail
NODO=${1:-archivo}; ENVF="$(cd "$(dirname "$0")/.." && pwd)/.env"; set -a; . "$ENVF"; set +a
# La cabecera de usuario lleva un nombre secreto (ARCHIVO_HEADER_ID): con Remote-User, cualquiera de la red interna podía suplantar a otro
NID=$(python3 -c 'import json,glob,sys;f=glob.glob("/home/'"$USER"'/GNS3/projects/*/ACC-Lab.gns3")[0];print([n["node_id"] for n in json.load(open(f))["topology"]["nodes"] if n["name"]==sys.argv[1]][0])' "$NODO")
D=$(ls -d ~/GNS3/projects/*/project-files/docker/$NID)
fb() { docker run --rm --entrypoint filebrowser -v "$D/database:/database" -v "$D/srv:/srv" filebrowser/filebrowser:v2.63.23 -d /database/filebrowser.db "$@"; }
fb config set --auth.method=proxy --auth.header="X-Acc-${ARCHIVO_HEADER_ID:?gen-secrets.sh}" --createUserDir --branding.name "Archivo digital · Alcaldía Digital" >/dev/null
mkdir -p "$D/srv/users" "$D/srv/sedes" 2>/dev/null || true
fb config cat | grep -iE "auth method|create user dir|branding" 
