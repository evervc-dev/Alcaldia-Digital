#!/bin/bash
# Abre el escritorio del usuario en ts1 (10.10.20.40). La pantalla de login de xrdp pide usuario/contraseña del AD.
echo "Conectando al servidor de escritorios ts1 (10.10.20.40:3389)..."
xfreerdp /v:10.10.20.40 /cert:ignore /size:1280x800 /sec:tls +clipboard 2>/dev/null
echo "Sesión cerrada. Enter para reconectar."; read -r _; exec "$0"
