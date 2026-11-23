#!/bin/bash
# Crea la plantilla QEMU de Windows 11 (instalación desatendida + sysprep) en ~/Documents/acc-project/plantillas. Contraseña local aleatoria en PLANTILLAS.md (600).
# Uso: plantilla-windows.sh <windows.iso> <virtio-win.iso>      Progreso: vncviewer 127.0.0.1:5977   Termina solo (se apaga).
set -euo pipefail; ISO=$(realpath "$1"); VIO=$(realpath "$2"); cd "$(dirname "$0")/.."; W=~/Documents/acc-project/plantillas; umask 077; mkdir -p "$W/cfg/acc"
D=$W/windows11-acc.qcow2; [ -e "$D" ] && { echo "ya existe $D"; exit 1; }
PW="Win-$(openssl rand -base64 18 | tr -d '/+=lIO0' | cut -c1-12)-7"; T=config/plantillas/windows
printf '| Windows 11 (plantilla) | `acc-local` | `%s` |\n' "$PW" >> "$W/PLANTILLAS.md"
A="<AutoLogon><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>acc-local</Username><Password><Value>$PW</Value><PlainText>true</PlainText></Password></AutoLogon><FirstLogonCommands><SynchronousCommand wcm:action=\"add\"><Order>1</Order><CommandLine>cmd /c for %d in (D E F G H) do if exist %d:\\acc\\preparar.cmd call %d:\\acc\\preparar.cmd</CommandLine></SynchronousCommand></FirstLogonCommands>"
PW="$PW" A="$A" python3 - "$T/autounattend.xml.tpl" "$W/cfg" <<'PY'
import os,sys,re,xml.dom.minidom as x
t=open(sys.argv[1]).read().replace("@PASS@",os.environ["PW"]); d=sys.argv[2]
a=t.replace("@AUTO@",os.environ["A"]); c=re.sub(r' <settings pass="windowsPE">.*?</settings>\n','',t.replace("@AUTO@",""),flags=re.S)
for n,v in (("autounattend.xml",a),("acc/clon.xml",c)): x.parseString(v.encode()); open(f"{d}/{n}","w").write(v)
PY
cp $T/unir.ps1 "$W/cfg/acc/"; sed 's/$/\r/' $T/preparar.cmd > "$W/cfg/acc/preparar.cmd"
bsdtar -cf "$W/cfg.iso" --format=iso9660 -C "$W/cfg" . ; qemu-img create -q -f qcow2 "$D" 60G
exec qemu-system-x86_64 -name plantilla-win -enable-kvm -machine q35 -cpu host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time -smp 4 -m 4096 -rtc base=localtime -vga std -usb -device usb-tablet -nic none \
 -device ich9-ahci,id=a -drive if=none,id=d0,file="$D",format=qcow2,cache=unsafe,discard=unmap -device ide-hd,bus=a.0,drive=d0,bootindex=1 \
 -drive if=none,id=c0,media=cdrom,readonly=on,file="$ISO" -device ide-cd,bus=a.1,drive=c0,bootindex=2 -drive if=none,id=c1,media=cdrom,readonly=on,file="$VIO" -device ide-cd,bus=a.2,drive=c1 \
 -drive if=none,id=c2,media=cdrom,readonly=on,file="$W/cfg.iso" -device ide-cd,bus=a.3,drive=c2 -display none -vnc 127.0.0.1:77 -qmp unix:"$W/qmp.sock",server=on,wait=off
