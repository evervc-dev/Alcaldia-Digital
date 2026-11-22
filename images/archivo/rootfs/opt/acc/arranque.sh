#!/bin/sh
# Respaldo (si existe /config/acc/respaldo.env, en volumen) + filebrowser como 'user'
[ -x /config/acc/respaldo.sh ] && /config/acc/respaldo.sh bucle &   # F9: respaldo diario (script y env en el volumen /config)
exec setuidgid user tini -- /init.sh "$@"
