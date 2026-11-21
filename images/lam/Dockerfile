# acc/lam: LDAP Account Manager 9.6 para el AD (gestión de cuentas por TI, PLAN §12).
# + iproute2 (bonds GNS3) + CA del laboratorio (LDAPS validado) + config persistente + perfil AD generado al arrancar.
FROM ghcr.io/ldapaccountmanager/lam:9.6
USER root
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 iputils-ping && rm -rf /var/lib/apt/lists/*
COPY rootfs/ /
RUN update-ca-certificates >/dev/null && printf 'TLS_CACERT /etc/ssl/certs/ca-certificates.crt\nTLS_REQCERT demand\n' > /etc/ldap/ldap.conf \
 && cp -a /var/lib/ldap-account-manager/config /opt/acc/config-default && chmod +x /opt/acc/*.sh
VOLUME ["/var/lib/ldap-account-manager/config", "/etc/acc"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
