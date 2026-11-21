#!/bin/bash
# Si el dominio ya está provisionado (estado en el volumen) arranca samba; si no, deja la consola lista para F4.
if [ -f /var/lib/samba/private/sam.ldb ]; then
  samba -D && echo "[acc] samba AD DC iniciado"
else
  echo "[acc] dominio NO provisionado: ejecutar el procedimiento de F4"
fi
exec /bin/bash -l
