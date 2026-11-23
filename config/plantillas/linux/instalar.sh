#!/bin/bash
# Lo ejecuta cloud-init UNA vez al construir la plantilla (scripts/plantilla-linux.sh). Termina apagando.
set -eux; export DEBIAN_FRONTEND=noninteractive; S=/mnt/seed
rm -f /etc/resolv.conf; echo "nameserver 1.1.1.1" > /etc/resolv.conf   # solo durante la construcción
for i in 1 2 3 4 5 6; do apt-get update --error-on=any && break; [ $i = 6 ] && exit 1; ip -4 -br a; sleep 10; done; apt-get -y purge openssh-server || true
apt-get install -y --no-install-recommends xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-terminal xfce4-settings thunar mousepad dbus-x11 xserver-xorg lightdm lightdm-gtk-greeter \
  winbind libnss-winbind libpam-winbind krb5-user samba-common-bin firefox-esr fonts-dejavu locales zenity network-manager network-manager-gnome ldap-utils bind9-dnsutils iputils-ping curl freerdp3-x11 sudo ca-certificates console-setup
sed -i 's/^# *es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen; locale-gen; update-locale LANG=es_ES.UTF-8; timedatectl set-timezone America/El_Salvador || ln -sf /usr/share/zoneinfo/America/El_Salvador /etc/localtime
sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="latam"/' /etc/default/keyboard
mkdir -p /opt/acc /var/lib/samba/acc /home/ALCALDIA; cp $S/acc/* /opt/acc/; chmod 755 /opt/acc/*.sh /opt/acc/*.py; ln -s /opt/acc/unir-dominio.sh /usr/local/sbin/unir-dominio
cp /opt/acc/krb5.conf /etc/krb5.conf; cp /opt/acc/alcaldia-lab-ca.crt /usr/local/share/ca-certificates/; update-ca-certificates
pam-auth-update --enable winbind --enable mkhomedir
sed -i 's/^passwd:.*/passwd:         files winbind/; s/^group:.*/group:          files winbind/' /etc/nsswitch.conf
cp /opt/acc/01acc-horario /etc/X11/Xsession.d/01acc-horario; touch /var/log/acc-horario.log; chmod 622 /var/log/acc-horario.log
mkdir -p /etc/lightdm/lightdm.conf.d; printf '[Seat:*]\ngreeter-hide-users=true\ngreeter-show-manual-login=true\nallow-guest=false\nuser-session=xfce\n' > /etc/lightdm/lightdm.conf.d/60-acc.conf
printf '%%rol-admin ALL=(ALL) ALL\n%%rol-ti ALL=(ALL) ALL\n' > /etc/sudoers.d/acc; chmod 440 /etc/sudoers.d/acc
printf '[Unit]\nDescription=ACC: horarios y accesos de emergencia\nAfter=network-online.target winbind.service\n[Service]\nExecStart=/usr/bin/python3 /opt/acc/acc-acceso.py agente\nRestart=always\nRestartSec=15\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/acc-acceso.service
systemctl enable acc-acceso lightdm NetworkManager; systemctl disable winbind || true; systemctl set-default graphical.target
rm -f /etc/netplan/*.yaml /etc/network/interfaces.d/*; printf 'auto lo\niface lo inet loopback\n' > /etc/network/interfaces; systemctl disable systemd-networkd || true
rm -f /etc/resolv.conf; systemctl disable systemd-resolved 2>/dev/null || true
cloud-init clean --logs || true; touch /etc/cloud/cloud-init.disabled; truncate -s 0 /etc/machine-id; rm -f /var/lib/dbus/machine-id; apt-get clean; umount $S || true
touch /opt/acc/plantilla-lista; sync; (sleep 3; poweroff) &
