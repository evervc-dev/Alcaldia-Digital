# acc/pc: PC de funcionario / atacante / canario
FROM alpine:3.20
RUN apk add --no-cache bash curl bind-tools openldap-clients nmap nmap-scripts hydra \
      iperf3 iproute2 iputils tcpdump openssh-client procps
VOLUME ["/data"]
CMD ["/bin/bash", "-l"]
