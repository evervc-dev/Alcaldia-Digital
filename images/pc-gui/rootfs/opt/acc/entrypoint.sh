#!/bin/bash
# Con consola VNC, GNS3 exporta DISPLAY (Xvfb del host). Escritorio mínimo con accesos directos.
if [ -n "$DISPLAY" ]; then
  fluxbox >/dev/null 2>&1 &
  sleep 1
  xterm -geometry 100x20+10+10 -title "Escritorio remoto (RDP a ts1)" -e /opt/acc/rdp.sh &
fi
exec /bin/bash -l
