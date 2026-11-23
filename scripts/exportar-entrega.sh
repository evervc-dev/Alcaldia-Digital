#!/bin/bash
# Entrega de la simulación (enunciado §7): proyecto exportado de GNS3, diagrama, configuraciones y plan de pruebas.
# Genera, FUERA del repositorio, ~/Documents/acc-project/entrega/:
#   ACC-Lab-topologia-<fecha>.gns3project  topología (nodos, enlaces, plantillas, dibujos) SIN volúmenes ni discos:
#                                          el estado se reconstruye con el código del repositorio (IaC) y gen-secrets.sh.
#   diagrama/  configs/  pruebas/  inventario/  IMAGENES.md  LEEME.md
#   privado/ACC-Lab-completo-<fecha>.gns3project   exportación COMPLETA de GNS3 (con estado y SECRETOS): no se comparte.
# Uso: exportar-entrega.sh [--sin-completo | --solo-completo]
#   La exportación completa exige TODOS los nodos detenidos (GNS3: «Project must be stopped»): hacerla al apagar el lab.
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
REPO=$(pwd); OUT=$(dirname "$REPO")/entrega; F=$(date +%Y-%m-%d)
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename); PDIR=~/GNS3/projects/$PID
mkdir -p "$OUT"/{diagrama,configs,pruebas,inventario,privado}; chmod 700 "$OUT/privado"
if [ "${1:-}" != --solo-completo ]; then

# 1) topología portátil (solo el .gns3)
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT
cp "$PDIR/ACC-Lab.gns3" "$TMP/ACC-Lab.gns3"
( cd "$TMP" && python3 -I -c 'import zipfile; z=zipfile.ZipFile("t.gns3project","w",zipfile.ZIP_DEFLATED); z.write("ACC-Lab.gns3"); z.close()' )
cp "$TMP/t.gns3project" "$OUT/ACC-Lab-topologia-$F.gns3project"
echo "topología: $OUT/ACC-Lab-topologia-$F.gns3project ($(du -h "$OUT/ACC-Lab-topologia-$F.gns3project" | cut -f1))"

# 2) diagrama, configuraciones saneadas, pruebas e inventario
cp topology/topologia.png topology/topologia.svg "$OUT/diagrama/"
cp configs/* "$OUT/configs/"
cp -r docs/pruebas/. "$OUT/pruebas/"; cp docs/PROCEDIMIENTOS-DR.md "$OUT/pruebas/"
cp inventory/ipam.md topology/topologia.md RESUMEN.md "$OUT/inventario/"

# 3) imágenes (nombre y versión; no se incluyen: se construyen con scripts/build-images.sh)
{
  echo "# Imágenes usadas en la simulación ($F)"
  echo
  echo "Ninguna imagen está sujeta a licencia comercial (todas son libres), pero **no se incluyen** por tamaño: las imágenes \`acc/*\` se construyen con \`scripts/build-images.sh\` a partir de los \`Dockerfile\` de \`images/\`, y OPNsense se descarga con \`scripts/get-opnsense.sh\`."
  echo
  echo "| Imagen | Versión / etiqueta | Base | Id |"; echo "|---|---|---|---|"
  for t in $(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print("\n".join(sorted({n["properties"]["image"] for n in d["topology"]["nodes"] if n["node_type"]=="docker"})))' "$PDIR/ACC-Lab.gns3"); do
    base=$(grep -m1 -h '^FROM' "images/$(echo "$t" | sed 's|acc/||; s|:.*||')/Dockerfile" 2>/dev/null | awk '{print $2}' || true)
    case "$t" in acc/zabbix-server*) base=zabbix/zabbix-server-pgsql:alpine-7.0-latest ;; acc/zabbix-web*) base=zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest ;; esac
    echo "| \`${t%%:*}\` | ${t##*:} | ${base:-—} | \`$(docker image inspect -f '{{.Id}}' "$t" 2>/dev/null | cut -c8-19)\` |"
  done
  echo "| OPNsense (QEMU, fw-a1/fw-a2/fw-b) | $(ls ~/GNS3/images/QEMU/ | grep -E '^opnsense-.*-nano\.qcow2$' | sort -V | tail -1) | imagen *nano* oficial | — |"
  echo "| GNS3 | servidor $(curl -s "$GNS3_URL/v3/version" | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])' 2>/dev/null || echo '?') | — | — |"
} > "$OUT/IMAGENES.md"

cat > "$OUT/LEEME.md" <<EOF
# Entrega de la simulación — Alcaldía Digital ($F)

| Contenido | Dónde |
|---|---|
| Proyecto GNS3 (topología portátil: nodos, enlaces, plantillas y dibujos; sin volúmenes, discos ni imágenes) | \`ACC-Lab-topologia-$F.gns3project\` |
| Diagrama de la topología | \`diagrama/topologia.png\` y \`.svg\` |
| Configuraciones de los dispositivos (OPNsense, FRR, OVS; saneadas: sin contraseñas, claves ni PSK) | \`configs/\` |
| Plan de pruebas con resultados, tiempos y capturas | \`pruebas/\` (F10 = pruebas formales T1–T11) y \`pruebas/PROCEDIMIENTOS-DR.md\` |
| Direccionamiento IP, topología y resumen funcional | \`inventario/\` |
| Imágenes (nombre y versión) | \`IMAGENES.md\` |

**Reconstrucción** (infraestructura como código, repositorio Alcaldia-Digital):
\`build-images.sh\` → \`get-opnsense.sh\` → \`gns3-templates.sh\` → importar el \`.gns3project\` → \`gen-secrets.sh\` → \`deploy-config.sh\` / \`opn-apply.sh\` → \`ad-setup.sh\`, \`services-setup.sh\`, \`nas-setup.sh\`, \`respaldo-setup.sh\`, \`zbx-setup.sh\`, \`glpi-setup.sh\`, \`cf-setup.sh\` → \`lab-check.sh\`.
Los secretos no se entregan: se generan con \`gen-secrets.sh\` en el \`.env\` local.
EOF

# 4) guardia: ningún valor del .env en lo que se entrega (privado/ excluido)
fuga=0
while IFS='=' read -r k v; do v=${v//\'/}; [ ${#v} -ge 10 ] || continue; case $k in CF_ZONE|GNS3_USER|GNS3_URL) continue ;; esac
  if grep -rqF --exclude-dir=privado -- "$v" "$OUT" || unzip -p "$OUT/ACC-Lab-topologia-$F.gns3project" | grep -qF -- "$v"; then echo "¡SECRETO $k en la entrega!"; fuga=1; fi
done < <(grep -E '^[A-Z_]+=.+' .env)
[ $fuga = 0 ] && echo "guardia: la entrega no contiene ningún secreto del .env" || exit 1
fi

# 5) exportación completa (privada) por la API de GNS3
if [ "${1:-}" != --sin-completo ]; then
  TOKEN=$(curl -fsS -X POST "$GNS3_URL/v3/access/users/authenticate" -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,os;print(json.dumps({"username":os.environ["GNS3_USER"],"password":os.environ["GNS3_PASS"]}))')" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
  umask 077
  if curl -fsS -H "Authorization: Bearer $TOKEN" "$GNS3_URL/v3/projects/$PID/nodes" | python3 -c 'import sys,json; sys.exit(0 if any(n["status"]!="stopped" for n in json.load(sys.stdin)) else 1)'; then
    echo "completo: OMITIDO (hay nodos encendidos; GNS3 exige el proyecto detenido). Al apagar el lab: Stop all -> exportar-entrega.sh --solo-completo"
  else
  curl -fsS -H "Authorization: Bearer $TOKEN" -o "$OUT/privado/ACC-Lab-completo-$F.gns3project" \
    "$GNS3_URL/v3/projects/$PID/export?include_snapshots=false&include_images=false&reset_mac_addresses=false&keep_compute_ids=false&compression=zstd"
  echo "completo (PRIVADO, con secretos): $OUT/privado/ACC-Lab-completo-$F.gns3project ($(du -h "$OUT/privado/ACC-Lab-completo-$F.gns3project" | cut -f1))"
  fi
fi
echo "listo: $OUT"
