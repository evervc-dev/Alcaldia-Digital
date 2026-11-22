#!/bin/bash
# Siembra smb.conf si el volumen está vacío; si ya está unido al dominio, arranca winbind. Luego xrdp.
[ -f /etc/samba/smb.conf.acc ] || { cp /opt/acc/smb.conf /etc/samba/smb.conf; touch /etc/samba/smb.conf.acc; }
mkdir -p /home/ALCALDIA /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork 2>/dev/null || true
if [ -f /var/lib/samba/private/secrets.tdb ]; then winbindd && echo "[acc] winbind iniciado"; else echo "[acc] ts1 NO unido al dominio: ejecutar la unión (F5)"; fi
rm -f /var/run/xrdp/*.pid /run/dbus/pid   # PIDs de un arranque anterior (el contenedor se reutiliza)
/usr/sbin/xrdp-sesman && /usr/sbin/xrdp && echo "[acc] xrdp escuchando en :3389"
for d in /etc/acc /var/lib/samba/acc /config/acc /data/.acc; do [ -x $d/respaldo.sh ] && { $d/respaldo.sh bucle & break; }; done   # F9: respaldo diario
exec /bin/bash -l
