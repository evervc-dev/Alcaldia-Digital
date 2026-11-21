#!/bin/bash
# DATABASE_URL en /etc/acc/portal.env (volumen persistente, desde .env del host)
[ -f /etc/acc/portal.env ] && { set -a; . /etc/acc/portal.env; set +a; }
cd /opt/portal && ( while true; do uvicorn main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*' >> /var/log/portal.log 2>&1; sleep 5; done ) &
echo "[acc] portal en :8000"
exec /bin/bash -l
