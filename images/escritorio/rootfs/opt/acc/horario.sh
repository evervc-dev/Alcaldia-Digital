#!/bin/bash
# Se ejecuta al iniciar la sesión (startwm.sh en ts1, Xsession en los puestos): decide acc-acceso.py. Sale 1 -> se cierra la sesión.
M=$(/usr/bin/python3 /opt/acc/acc-acceso.py comprobar) && exit 0
MSG="Acceso no permitido ahora\n\nCuenta: <b>$(id -un)</b>\n${M:-no se pudo comprobar el permiso}\n\nHora actual: $(TZ=UTC6 date '+%d/%m/%Y %H:%M')\n\nEn una emergencia, un administrador o TI de guardia puede darle acceso temporal.\nLa sesión se cerrará al aceptar."
zenity --error --title="Alcaldía Digital · Acceso" --width=520 --text="$MSG" 2>/dev/null || xfce4-terminal --hide-menubar -T "Acceso" -x sh -c "printf '$M\n'; sleep 30"
exit 1
