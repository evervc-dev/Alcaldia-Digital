# acc/gate: control de horario para servicios web (nginx auth_request). Fuente única: logonHours del AD.
FROM alpine:3.20
RUN apk add --no-cache python3 py3-ldap3 tzdata iproute2 iputils bash
COPY rootfs/ /
VOLUME ["/etc/acc"]
CMD ["/bin/sh", "-c", "python3 /opt/acc/gate.py > /var/log/gate.log 2>&1 & exec /bin/sh"]
