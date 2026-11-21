# acc/kit-sede: kit estándar de sede (equivale al FortiGate 40F)
FROM acc/router:1.0
RUN apk add --no-cache strongswan dnsmasq
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/frr", "/etc/nftables.d", "/etc/snmp", "/etc/swanctl", "/etc/dnsmasq.d"]
CMD ["/opt/acc/entrypoint.sh"]
