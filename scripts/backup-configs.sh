#!/bin/bash
# F9: respaldo de las CONFIGURACIONES de los equipos de red (requisito del PDF §7).
#  1) Copia COMPLETA (con secretos) -> tar.gz en nas-a: respaldos/configuraciones/<fecha>.tar.gz (WORM COMPLIANCE 7 días,
#     replicada a nas-b). Es la que se usa para restaurar un equipo.
#  2) Copia SANEADA (contraseñas, claves, hashes, PSK y comunidades -> ***) en configs/ del repo: historial y diff en git.
# Equipos: OPNsense fw-a1/fw-a2/fw-b (config.xml), routers/kits FRR (running-config), switches OVS (ovs-vsctl show).
# Uso: backup-configs.sh          (después: git add configs && git commit)
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
FECHA=$(date +%Y-%m-%d_%H%M)
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/completo" configs

for f in fw-a1 fw-a2 fw-b; do
  bash scripts/fw.sh "$f" 'cat /conf/config.xml' > "$TMP/completo/$f.config.xml" && echo "  $f: config.xml ($(wc -c < "$TMP/completo/$f.config.xml") bytes)"
done
for n in isp1 isp2 inet-core kit-sede-01 kit-sede-02 kit-sede-03; do
  docker exec "GNS3.$n.$PID" vtysh -c 'show running-config' > "$TMP/completo/$n.frr.conf" 2>/dev/null && echo "  $n: FRR running-config"
done
for n in sw-a1 sw-a2 wsw-a1 wsw-a2 sw-b1 sw-b2 sw-sede-01 sw-sede-02 sw-sede-03; do
  docker exec "GNS3.$n.$PID" ovs-vsctl show > "$TMP/completo/$n.ovs.txt" 2>/dev/null && echo "  $n: OVS"
done

# 1) completa -> nas-a (WORM)
tar -C "$TMP/completo" -czf "$TMP/configs.tar.gz" .
docker exec -e RP="$MINIO_ROOT_PASS" -i "GNS3.nas-a.$PID" sh -c \
  "mc alias set a http://127.0.0.1:9000 admin-nas \"\$RP\" >/dev/null && mc pipe a/respaldos/configuraciones/$FECHA.tar.gz >/dev/null" < "$TMP/configs.tar.gz"
echo "completa -> nas-a: respaldos/configuraciones/$FECHA.tar.gz ($(wc -c < "$TMP/configs.tar.gz") bytes, WORM)"

# 2) saneada -> configs/ (git)
python3 -I - "$TMP/completo" configs <<'PY'
import re, sys, pathlib
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
# solo etiquetas cuyo NOMBRE completo es de secreto (no rekey_time, keyingtries, passive...)
SECRET_TAG = re.compile(r'<([\w.-]*(?:pass|password|passwd|secret|key|hash|psk|prv|privkey|community|token|seed))>(.*?)</\1>', re.I | re.S)
for f in sorted(src.iterdir()):
    t = f.read_text(errors="replace")
    if f.name.endswith(".xml"):
        t = SECRET_TAG.sub(lambda m: f"<{m.group(1)}>***</{m.group(1)}>" if m.group(2).strip() else m.group(0), t)
        t = re.sub(r'(<authorizedkeys>)[^<]*(</authorizedkeys>)', r'\1***\2', t)
        t = re.sub(r'(<revision>.*?</revision>)', '<revision>(omitida)</revision>', t, flags=re.S)   # evita ruido en el diff
    else:
        t = re.sub(r'(?im)^(\s*(?:password|enable password|ip ospf authentication-key|ip ospf message-digest-key.*?md5)\s+)\S+', r'\1***', t)
        t = re.sub(r'(?m)^(Building configuration|Current configuration).*\n', '', t)
    (dst / f.name).write_text(t)
PY
# Guardia: ningún valor del .env puede aparecer en configs/
fuga=0; while IFS='=' read -r k v; do v=${v//\'/}; [ ${#v} -ge 10 ] || continue; case $k in CF_ZONE|GNS3_USER) continue ;; esac   # valores públicos
  grep -rqF -- "$v" configs/ && { echo "¡SECRETO $k encontrado en configs/! (no hacer commit)"; fuga=1; }
done < <(grep -E '^[A-Z_]+=.+' .env)
[ $fuga = 0 ] && echo "saneada -> configs/ ($(ls configs | wc -l) archivos, sin secretos del .env). Ahora: git add configs && git commit"
