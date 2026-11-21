# acc/router: router/ISP ligero (FRR + nftables + SNMP)
FROM alpine:3.20
RUN apk add --no-cache bash frr nftables iproute2 iputils net-snmp net-snmp-tools \
      tcpdump iperf3 curl ethtool bind-tools procps \
 && mkdir -p /opt/acc/defaults && cp -a /etc/frr /opt/acc/defaults/frr \
 && sed -i "s/^bgpd=no/bgpd=yes/; s/^ospfd=no/ospfd=yes/" /etc/frr/daemons /opt/acc/defaults/frr/daemons
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
# Estado persistente (GNS3 conserva además /etc/network)
VOLUME ["/etc/frr", "/etc/nftables.d", "/etc/snmp"]
CMD ["/opt/acc/entrypoint.sh"]
