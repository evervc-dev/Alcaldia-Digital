#!/bin/sh
# Vigilante de túneles del kit: cada 30 s relanza los túneles que no estén ESTABLISHED.
# Motivo: si el kit arranca antes que el OPNsense del sitio, este responde NO_PROPOSAL_CHOSEN mientras carga
# su configuración y strongSwan NO reintenta ante ese error (keyingtries solo cubre la falta de respuesta).
sleep 60
while true; do
  for c in $(swanctl --list-conns 2>/dev/null | sed -n 's/^\([a-z0-9-]*\): IKEv2.*/\1/p'); do
    if ! swanctl --list-sas --ike "$c" 2>/dev/null | grep -q ESTABLISHED; then
      echo "$(date -Is) $c sin SA: relanzando" >> /var/log/vigia-tuneles.log
      swanctl --initiate --child "$c" --timeout 20 >/dev/null 2>&1 &
    fi
  done
  sleep 30
done
