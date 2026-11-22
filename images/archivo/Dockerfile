# acc/archivo: filebrowser oficial + restic para el respaldo diario (F9).
# GNS3 arranca como root: se lanza el bucle de respaldo y filebrowser sigue como el usuario 'user' de la imagen.
FROM restic/restic:0.17.3 AS restic
FROM filebrowser/filebrowser:v2.63.23
USER root
COPY --from=restic /usr/bin/restic /usr/local/bin/restic
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
ENTRYPOINT ["/opt/acc/arranque.sh"]
