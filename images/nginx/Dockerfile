# acc/nginx: nginx 1.27 oficial con /etc/nginx/conf.d persistente (la imagen oficial no lo declara como volumen)
FROM nginx:1.27-alpine
RUN apk add --no-cache bash iproute2 iputils curl && mv /etc/nginx/conf.d/default.conf /etc/nginx/default.conf.orig
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/nginx/conf.d"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
