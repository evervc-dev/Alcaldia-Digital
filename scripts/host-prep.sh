#!/bin/bash
# Prepara el host Arch (ejecutar con sudo): carga los módulos que usan los nodos y los deja persistentes.
set -euo pipefail
MODS="bonding openvswitch 8021q"
for m in $MODS; do modprobe "$m" && echo "módulo $m cargado"; done
printf '%s\n' $MODS > /etc/modules-load.d/acc-gns3.conf
echo "Persistente en /etc/modules-load.d/acc-gns3.conf"
lsmod | grep -E '^(bonding|openvswitch|8021q)'

# busybox estático: GNS3 lo inyecta en los contenedores Docker para configurar la red
pacman -Q busybox >/dev/null 2>&1 || pacman -S --noconfirm busybox
file -L "$(command -v busybox)" | grep -q 'statically linked' && echo "busybox estático OK" || echo "AVISO: busybox no es estático"
