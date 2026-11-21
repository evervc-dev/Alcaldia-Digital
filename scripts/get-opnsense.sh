#!/bin/bash
# Descarga la imagen nano de OPNsense, verifica SHA256 y la convierte a qcow2 para GNS3.
# Uso: bash get-opnsense.sh [VERSION]   (sin versión: la más reciente publicada)
set -euo pipefail
MIRROR=${OPN_MIRROR:-https://pkg.opnsense.org/releases}
VER=${1:-$(curl -fsSL "$MIRROR/" | grep -oE 'href="[0-9]+\.[0-9]+/"' | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -1)}
DL=${DL_DIR:-$HOME/Downloads/opnsense-$VER}; OUT=$HOME/GNS3/images/QEMU
mkdir -p "$DL" "$OUT"
IMG="OPNsense-$VER-nano-amd64.img"
cd "$DL"
curl -fL -C - -o "$IMG.bz2" "$MIRROR/$VER/$IMG.bz2"
curl -fsSL -o sums.txt "$MIRROR/$VER/OPNsense-$VER-checksums-amd64.sha256"
grep "$IMG.bz2" sums.txt | sed -E 's/^SHA256 \((.*)\) = (.*)$/\2  \1/' | sha256sum -c -
[ -f "$IMG" ] || bunzip2 -k "$IMG.bz2"
qemu-img convert -O qcow2 "$IMG" "$OUT/opnsense-$VER-nano.qcow2"
qemu-img resize "$OUT/opnsense-$VER-nano.qcow2" 8G
echo "Listo: $OUT/opnsense-$VER-nano.qcow2"
