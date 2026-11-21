#!/bin/bash
# Siembra la config por defecto si el volumen está vacío, aplica el perfil AD (/etc/acc/lam-perfil.json + secretos de
# /etc/acc/lam.env) y arranca LAM (apache) con reintento. Consola: bash.
C=/var/lib/ldap-account-manager/config
[ -f $C/config.cfg ] || cp -a /opt/acc/config-default/. $C/
[ -f /etc/acc/lam.env ] && [ -f /etc/acc/lam-perfil.json ] && php /opt/acc/lam-config.php && echo "[acc] perfil AD aplicado"
chown -R www-data:www-data $C 2>/dev/null || true
export LAM_SKIP_PRECONFIGURE=true
( while true; do /usr/local/bin/start.sh >> /var/log/lam.log 2>&1; sleep 5; done ) &
echo "[acc] LAM en :80"
exec /bin/bash -l
