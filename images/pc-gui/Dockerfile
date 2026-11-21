# acc/pc-gui: PC de funcionario con interfaz gráfica (consola VNC de GNS3): cliente RDP + navegador.
FROM alpine:3.20
RUN apk add --no-cache bash fluxbox xterm freerdp firefox font-dejavu ttf-dejavu dbus-x11 \
      curl bind-tools iproute2 iputils ca-certificates tzdata
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/data"]
CMD ["/opt/acc/entrypoint.sh"]
