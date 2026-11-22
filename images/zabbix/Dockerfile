# acc/zabbix-{server,web}: imágenes oficiales Zabbix 7.0 LTS (alpine) adaptadas a GNS3:
# GNS3 necesita arrancar como root con shell (la oficial usa el usuario zabbix con /sbin/nologin).
# El proceso oficial se ejecuta como 'zabbix' con su-exec; credenciales en /etc/acc/zbx.env (volumen, desde .env).
ARG BASE
FROM ${BASE}
ARG ACC_CMD
USER root
RUN apk add --no-cache su-exec bash psqlodbc   # psqlodbc: comprobación de la réplica (RPO) por ODBC
ENV ACC_CMD=${ACC_CMD}
COPY rootfs/ /
# F9: restic (binario estático oficial) para los respaldos
COPY --from=restic/restic:0.17.3 /usr/bin/restic /usr/local/bin/restic
RUN chmod +x /opt/acc/entrypoint.sh
VOLUME ["/etc/acc"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
