# acc/authelia: Authelia 4.39.28 oficial con /config persistente y arranque diferido hasta que exista la configuración
FROM authelia/authelia:4.39.28
RUN sed -i 's|:/bin/bash$|:/bin/sh|' /etc/passwd   # GNS3 usa "su" y la imagen no trae bash
COPY rootfs/ /
VOLUME ["/config"]
ENTRYPOINT []
CMD ["/bin/sh", "/opt/acc/entrypoint.sh"]
