# acc/nas: NAS de respaldo (equivale al RS1226RP+): MinIO con Object Lock + mc + restic
FROM alpine:3.20
RUN apk add --no-cache bash minio minio-client restic curl iproute2 iputils tzdata ca-certificates \
 && ln -sf /usr/bin/mcli /usr/local/bin/mc
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/data"]
CMD ["/opt/acc/entrypoint.sh"]
