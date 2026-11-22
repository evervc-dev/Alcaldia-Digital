#!/bin/bash
# Descarga las imágenes oficiales con versión fijada (MVP).
set -euo pipefail
IMAGES=(
  gns3/openvswitch:latest
  postgres:16-alpine
  nginx:1.27-alpine
  redis:7-alpine
  authelia/authelia:4.39.28
  filebrowser/filebrowser:v2.63.23
  cloudflare/cloudflared:2026.10.7
  zabbix/zabbix-server-pgsql:alpine-7.0-latest
  zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest
  zabbix/zabbix-agent2:alpine-7.0-latest
  axllent/mailpit:latest
  cgr.dev/chainguard/minio:latest
)
for i in "${IMAGES[@]}"; do echo "== $i"; docker pull -q "$i"; done
docker pull -q restic/restic:0.17.3   # F9: binario estático de restic para las imágenes
