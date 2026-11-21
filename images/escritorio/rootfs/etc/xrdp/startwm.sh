#!/bin/sh
# Sesión XFCE del usuario del dominio. Antes: política de horario laboral (mensaje + cierre si no corresponde).
[ -r /etc/default/locale ] && . /etc/default/locale
export LANG=es_ES.UTF-8
/opt/acc/horario.sh || exit 0
exec dbus-launch --exit-with-session startxfce4
