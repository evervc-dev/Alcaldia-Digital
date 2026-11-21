# acc/pg: PostgreSQL 16 oficial + espera de credenciales en /etc/acc/pg.env (persistente, desde .env; nunca en GNS3/git)
FROM postgres:16-alpine
RUN apk add --no-cache bash iproute2 iputils
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/acc"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
