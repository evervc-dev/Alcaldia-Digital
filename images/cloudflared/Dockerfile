# acc/cloudflared: conector de Cloudflare Tunnel (binario oficial 2026.10.7) sobre Alpine (GNS3 necesita /bin/sh)
FROM cloudflare/cloudflared:2026.10.7 AS cf
FROM alpine:3.20
RUN apk add --no-cache bash ca-certificates iproute2 iputils curl tzdata
COPY --from=cf /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/acc"]
CMD ["/opt/acc/entrypoint.sh"]
