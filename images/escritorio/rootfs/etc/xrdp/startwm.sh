#!/bin/sh
# Sesión XFCE del usuario del dominio
[ -r /etc/default/locale ] && . /etc/default/locale
export LANG=es_ES.UTF-8
exec dbus-launch --exit-with-session startxfce4
