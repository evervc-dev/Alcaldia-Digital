# acc/portal: Portal de trámites (S2). Público: catálogo, solicitud y consulta por folio.
# /funcionarios: bandeja protegida por Authelia (MFA) vía nginx; usa la cabecera Remote-User.
FROM python:3.12-alpine
RUN apk add --no-cache bash iproute2 iputils postgresql16-client tzdata \
 && pip install --no-cache-dir fastapi==0.115.6 uvicorn==0.32.1 "psycopg[binary]==3.2.3" python-multipart==0.0.20
COPY app/ /opt/portal/
COPY rootfs/ /
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/acc"]
CMD ["/opt/acc/entrypoint.sh"]
