#!/bin/bash
# Configura filebrowser (nodo "archivo") con el nodo DETENIDO: autenticación por cabecera Remote-User (Authelia)
# y carpeta personal automática /users/<usuario>. Usa un contenedor temporal (--rm) sobre el volumen del proyecto.
set -euo pipefail
NID=$(python3 -c 'import json,glob;f=glob.glob("/home/'"$USER"'/GNS3/projects/*/ACC-Lab.gns3")[0];print([n["node_id"] for n in json.load(open(f))["topology"]["nodes"] if n["name"]=="archivo"][0])')
D=$(ls -d ~/GNS3/projects/*/project-files/docker/$NID)
fb() { docker run --rm --entrypoint filebrowser -v "$D/database:/database" -v "$D/srv:/srv" filebrowser/filebrowser:v2.63.23 -d /database/filebrowser.db "$@"; }
fb config set --auth.method=proxy --auth.header=Remote-User --createUserDir --branding.name "Archivo digital · Alcaldía Digital" >/dev/null
mkdir -p "$D/srv/users" "$D/srv/sedes" 2>/dev/null || true
fb config cat | grep -iE "auth method|create user dir|branding" 
