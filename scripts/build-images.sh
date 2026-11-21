#!/bin/bash
# Construye las imágenes propias acc/* (el orden importa: kit-sede hereda de router).
set -euo pipefail
cd "$(dirname "$0")/../images"
for r in router kit-sede pc samba-dc; do
  echo "== acc/$r:1.0"; docker build -q -t "acc/$r:1.0" "$r"
done
docker images 'acc/*'
