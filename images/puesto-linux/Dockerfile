# acc/puesto-linux: puesto de funcionario Debian 13 + XFCE unido al dominio, con login gráfico LightDM (consola VNC de GNS3).
# Base: acc/escritorio (winbind, pam_mkhomedir, horario.sh, zenity). El horario se aplica al abrir la sesión.
FROM acc/escritorio:1.0
RUN apt-get update && apt-get install -y --no-install-recommends lightdm lightdm-gtk-greeter && rm -rf /var/lib/apt/lists/*
COPY rootfs/ /
RUN chmod +x /opt/acc/puesto.sh && touch /var/log/acc-horario.log && chmod 622 /var/log/acc-horario.log
CMD ["/opt/acc/puesto.sh"]
