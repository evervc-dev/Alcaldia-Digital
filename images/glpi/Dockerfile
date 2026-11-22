# acc/glpi: GLPI 11 oficial (mesa de servicio, mesa.evervc.dev) adaptado a GNS3: arranca como root con shell,
# credenciales en /etc/acc/glpi.env (volumen, desde .env) y GLPI corre como www-data. + CA del lab (LDAPS validado).
FROM glpi/glpi:11.0.11
USER root
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 && rm -rf /var/lib/apt/lists/*
COPY rootfs/ /
COPY --from=restic/restic:0.17.3 /usr/bin/restic /usr/local/bin/restic
RUN a2enmod -q headers && a2enconf -q acc-sso && update-ca-certificates >/dev/null && mkdir -p /etc/ldap \
 && printf 'TLS_CACERT /etc/ssl/certs/ca-certificates.crt\nTLS_REQCERT demand\n' > /etc/ldap/ldap.conf && chmod +x /opt/acc/*.sh
VOLUME ["/var/glpi", "/etc/acc"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
