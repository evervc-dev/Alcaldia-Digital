#!/bin/bash
# Crea (de forma idempotente) las plantillas ACC-* en el servidor GNS3 v3 usando su API REST.
# gns3-mcp no puede crear plantillas; este script es la única llamada directa a la API.
# Requiere GNS3_URL, GNS3_USER y GNS3_PASS en .env
set -euo pipefail
cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
: "${GNS3_PASS:?Rellena GNS3_PASS en .env}"
OPN_IMG=${OPN_IMG:-$(ls ~/GNS3/images/QEMU/ | grep -E '^opnsense-.*-nano\.qcow2$' | sort -V | tail -1 || true)}

TOKEN=$(curl -fsS -X POST "$GNS3_URL/v3/access/users/authenticate" -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,os;print(json.dumps({"username":os.environ["GNS3_USER"],"password":os.environ["GNS3_PASS"]}))')" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')
EXISTING=$(curl -fsS "${AUTH[@]}" "$GNS3_URL/v3/templates" | python3 -c 'import sys,json;[print(t["name"]) for t in json.load(sys.stdin)]')

TEMPLATES_JSON=$(curl -fsS "${AUTH[@]}" "$GNS3_URL/v3/templates")
create() { # nombre json   (UPDATE=1 actualiza las que ya existen)
  if grep -qxF "$1" <<<"$EXISTING"; then
    if [ "${UPDATE:-0}" = 1 ]; then
      id=$(python3 -c 'import json,sys;print(next(t["template_id"] for t in json.loads(sys.argv[1]) if t["name"]==sys.argv[2]))' "$TEMPLATES_JSON" "$1")
      curl -fsS -X PUT "${AUTH[@]}" "$GNS3_URL/v3/templates/$id" -d "$2" >/dev/null && echo "~ $1 (actualizada)"
    else echo "= $1 (ya existe)"; fi
    return
  fi
  curl -fsS -X POST "${AUTH[@]}" "$GNS3_URL/v3/templates" -d "$2" >/dev/null && echo "+ $1"
}
docker_tpl() { # nombre imagen adaptadores consola categoria [env]
  create "$1" "$(python3 - "$@" <<'PY'
import json,sys
n,img,ad,con,cat=sys.argv[1:6]; env=sys.argv[6] if len(sys.argv)>6 else ""
print(json.dumps({"name":n,"template_type":"docker","image":img,"adapters":int(ad),
 "console_type":con,"category":cat,"environment":env,"compute_id":"local"}))
PY
)"
}

docker_tpl ACC-Router        acc/router:1.0                     6  telnet router
docker_tpl ACC-Kit-Sede      acc/kit-sede:1.0                   2  telnet firewall
docker_tpl ACC-PC            acc/pc:1.0                         2  telnet guest
docker_tpl ACC-OVS           gns3/openvswitch:latest           24  telnet switch
docker_tpl ACC-Samba-DC      acc/samba-dc:1.0                   2  telnet guest
docker_tpl ACC-Postgres      postgres:16-alpine                 2  telnet guest
docker_tpl ACC-Nginx2        acc/nginx:1.0                      2  telnet guest
docker_tpl ACC-Redis         redis:7-alpine                     2  telnet guest
docker_tpl ACC-Authelia2     acc/authelia:1.0                   2  telnet guest
docker_tpl ACC-Filebrowser   filebrowser/filebrowser:v2.63.23   2  none   guest
docker_tpl ACC-Cloudflared2  acc/cloudflared:1.0                2  telnet guest
docker_tpl ACC-Zabbix-Server2 acc/zabbix-server:1.0              2  telnet guest
docker_tpl ACC-Zabbix-Web2   acc/zabbix-web:1.0                 2  telnet guest
docker_tpl ACC-Mailpit       axllent/mailpit:latest             2  none   guest
docker_tpl ACC-MinIO         cgr.dev/chainguard/minio:latest    2  none   guest
docker_tpl ACC-NAS           acc/nas:1.0                        2  telnet guest
docker_tpl ACC-Escritorio    acc/escritorio:1.0                 2  telnet guest
docker_tpl ACC-Gate          acc/gate:1.0                       2  telnet guest
docker_tpl ACC-Portal        acc/portal:1.0                     2  telnet guest
docker_tpl ACC-PG            acc/pg:1.0                         2  telnet guest
docker_tpl ACC-LAM           acc/lam:1.0                        2  telnet guest
docker_tpl ACC-GLPI          acc/glpi:1.0                       2  telnet guest
docker_tpl ACC-GLPI-DB       acc/glpi-db:1.0                    2  telnet guest
create ACC-Puesto-Linux "$(python3 -c 'import json;print(json.dumps({"name":"ACC-Puesto-Linux","template_type":"docker","image":"acc/puesto-linux:1.0","adapters":1,"console_type":"vnc","console_resolution":"1280x800","category":"guest","compute_id":"local"}))')"
create ACC-PC-GUI "$(python3 -c 'import json;print(json.dumps({"name":"ACC-PC-GUI","template_type":"docker","image":"acc/pc-gui:1.0","adapters":1,"console_type":"vnc","console_resolution":"1366x768","category":"guest","compute_id":"local"}))')"

if [ -n "$OPN_IMG" ]; then
  create ACC-OPNsense "$(python3 -c 'import json,sys;print(json.dumps({"name":"ACC-OPNsense","template_type":"qemu","compute_id":"local","platform":"x86_64","category":"firewall","hda_disk_image":sys.argv[1],"ram":1536,"cpus":1,"adapters":5,"adapter_type":"virtio-net-pci","hda_disk_interface":"sata","console_type":"telnet","options":"-cpu host","on_close":"shutdown_signal"}))' "$OPN_IMG")"
else
  echo "! No hay imagen OPNsense en ~/GNS3/images/QEMU (ejecuta get-opnsense.sh)"
fi
# Puestos completos (plantilla-windows.sh / plantilla-linux.sh). Windows: reloj en hora local, si no Kerberos lo rechaza (6 h de diferencia)
puesto() { [ -f ~/GNS3/images/QEMU/"$2" ] || return 0; create "$1" "$(python3 -c 'import json,sys;n,i,ram,cpu,ifc,opt=sys.argv[1:];print(json.dumps({"name":n,"template_type":"qemu","compute_id":"local","platform":"x86_64","category":"guest","hda_disk_image":i,"hda_disk_interface":ifc,"ram":int(ram),"cpus":int(cpu),"adapters":1,"adapter_type":"virtio-net-pci","console_type":"vnc","options":opt,"on_close":"shutdown_signal","linked_clone":True}))' "$@")"; }
puesto ACC-Windows11 windows11-acc.qcow2 3072 2 sata   "-cpu host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time -rtc base=localtime -vga std -usb -device usb-tablet"
puesto ACC-Linux     linux-acc.qcow2     1536 2 virtio "-cpu host -vga std -usb -device usb-tablet"
