# acc/samba-dc: controlador de dominio AD + DNS interno (se provisiona en F4)
FROM debian:12-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      samba samba-ad-dc samba-ad-provision winbind krb5-user smbclient ldb-tools dnsutils iproute2 iputils-ping procps ca-certificates \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /opt/acc/defaults && cp -a /etc/samba /opt/acc/defaults/samba
COPY rootfs/ /
# F9: restic (binario estático oficial) para los respaldos
COPY --from=restic/restic:0.17.3 /usr/bin/restic /usr/local/bin/restic
RUN chmod +x /opt/acc/*.sh
VOLUME ["/var/lib/samba", "/etc/samba"]
CMD ["/opt/acc/entrypoint.sh"]
