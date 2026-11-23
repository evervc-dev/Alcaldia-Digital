#!/bin/bash
# Crea la plantilla QEMU de Linux (Debian 13 + XFCE, lista para unirse al dominio). Uso: plantilla-linux.sh <debian-13-generic-amd64.qcow2 verificado>
set -euo pipefail; B=$(realpath "$1"); cd "$(dirname "$0")/.."; W=~/Documents/acc-project/plantillas; umask 077; D=$W/linux-acc.qcow2; [ -e "$D" ] && { echo "ya existe $D"; exit 1; }
mkdir -p "$W/seed/acc"; PW="Lin-$(openssl rand -base64 18 | tr -d '/+=lIO0' | cut -c1-12)-7"; printf '| Linux (plantilla) | `acc-local` | `%s` |\n' "$PW" >> "$W/PLANTILLAS.md"
for f in images/escritorio/rootfs/opt/acc/{acc-acceso.py,acc_politica.py,horario.sh,smb.conf} images/escritorio/rootfs/etc/krb5.conf images/puesto-linux/rootfs/etc/X11/Xsession.d/01acc-horario images/lam/rootfs/usr/local/share/ca-certificates/alcaldia-lab-ca.crt config/plantillas/linux/unir-dominio.sh; do cp "$f" "$W/seed/acc/"; done
cp config/plantillas/linux/instalar.sh "$W/seed/"; echo "instance-id: acc-plantilla-$(date +%s)" > "$W/seed/meta-data"
cat > "$W/seed/user-data" <<Y
#cloud-config
users:
  - {name: acc-local, gecos: Cuenta local, groups: [sudo], shell: /bin/bash, lock_passwd: false, passwd: '$(openssl passwd -6 "$PW")'}
runcmd:
  - [sh, -c, "mkdir -p /mnt/seed && mount -o ro LABEL=cidata /mnt/seed && (bash /mnt/seed/instalar.sh > /dev/ttyS1 2>&1 || echo FALLO > /dev/ttyS1)"]
Y
bsdtar -cf "$W/seed.iso" --format=iso9660 --options='volume-id=cidata,joliet,rockridge=useful' -C "$W/seed" .
qemu-img create -q -f qcow2 -F qcow2 -b "$B" "$D.tmp" 20G; qemu-img convert -O qcow2 "$D.tmp" "$D" && unlink "$D.tmp"
exec qemu-system-x86_64 -name plantilla-lin -enable-kvm -cpu host -smp 3 -m 2048 -vga std -usb -device usb-tablet -nic user,model=virtio-net-pci -drive if=virtio,file="$D",format=qcow2,cache=unsafe,discard=unmap \
 -drive if=virtio,format=raw,readonly=on,file="$W/seed.iso" -smbios type=1,serial=ds=nocloud -display none -vnc 127.0.0.1:78 -serial file:"$W/linux-serie.log" -serial file:"$W/linux-inst.log" -qmp unix:"$W/qmp-l.sock",server=on,wait=off
