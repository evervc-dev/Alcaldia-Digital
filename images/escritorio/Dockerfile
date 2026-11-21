# acc/escritorio: servidor de escritorios (ts1). XFCE por RDP (xrdp 0.10) con cuentas del AD (winbind).
# /home/ALCALDIA/<usuario> se crea en el primer inicio de sesión (pam_mkhomedir). Horario: logonHours del AD.
FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=es_ES.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-terminal xfce4-settings thunar mousepad \
      dbus-x11 xrdp xorgxrdp winbind libnss-winbind libpam-winbind krb5-user samba-common-bin \
      firefox-esr fonts-dejavu locales zenity iproute2 iputils-ping procps ldap-utils ca-certificates \
 && sed -i 's/^# *es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen \
 && rm -rf /var/lib/apt/lists/* \
 && pam-auth-update --enable winbind --enable mkhomedir \
 && sed -i 's/^passwd:.*/passwd:         files winbind/; s/^group:.*/group:          files winbind/' /etc/nsswitch.conf \
 && adduser xrdp ssl-cert \
 && mkdir -p /opt/acc/defaults && cp -a /etc/samba /opt/acc/defaults/samba
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh /etc/xrdp/startwm.sh
VOLUME ["/home", "/var/lib/samba", "/etc/samba"]
CMD ["/opt/acc/entrypoint.sh"]
