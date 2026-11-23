#!/bin/bash
# Une este equipo al dominio.  sudo unir-dominio <nombre-equipo> [cuenta de Domain Admins = admin.dc]
set -euo pipefail; N=${1:?nombre del equipo (máx. 15)}; A=${2:-admin.dc}; [[ $N =~ ^[A-Za-z0-9-]{1,15}$ ]] || { echo "nombre no válido"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "use sudo"; exit 1; }
getent hosts ad.alcaldia.lab >/dev/null || { echo "no resuelve ad.alcaldia.lab: revise que el DNS sea 10.10.20.10"; exit 1; }
hostnamectl set-hostname "$N"; sed -i '/^127\.0\.1\.1/d' /etc/hosts; echo "127.0.1.1 $N.ad.alcaldia.lab $N" >> /etc/hosts
cp /opt/acc/smb.conf /etc/samba/smb.conf; net ads join -U "$A" && systemctl enable --now winbind && systemctl restart acc-acceso lightdm
