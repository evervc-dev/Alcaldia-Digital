#!/bin/bash
# Puesto unido al dominio: winbind (si ya está unido) + LightDM sobre el display X que exporta GNS3 (seat xremote).
[ -f /etc/samba/smb.conf.acc ] || { cp /opt/acc/smb.conf /etc/samba/smb.conf; touch /etc/samba/smb.conf.acc; }
mkdir -p /home/ALCALDIA /run/dbus; rm -f /run/dbus/pid; dbus-daemon --system --fork 2>/dev/null || true
if [ -f /var/lib/samba/private/secrets.tdb ]; then winbindd && echo "[acc] winbind iniciado"; else echo "[acc] puesto NO unido al dominio"; fi
if [ -n "${DISPLAY:-}" ]; then
  N=${DISPLAY#*:}; N=${N%%.*}
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat > /etc/lightdm/lightdm.conf.d/60-acc.conf <<EOC
[Seat:*]
type=xremote
xserver-hostname=
xserver-display-number=$N
greeter-session=lightdm-gtk-greeter
greeter-hide-users=true
greeter-show-manual-login=true
allow-guest=false
user-session=xfce
EOC
  ( while true; do lightdm >> /var/log/lightdm-acc.log 2>&1; sleep 5; done ) &
  echo "[acc] LightDM en el display $DISPLAY"
fi
( while true; do python3 /opt/acc/acc-acceso.py agente >> /var/log/acc-acceso.log 2>&1; sleep 5; done ) &   # horarios y excepciones
exec /bin/bash -l
