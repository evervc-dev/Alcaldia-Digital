#!/bin/bash
# CA del laboratorio + certificados LDAPS para dc1/dc2 (el autofirmado de Samba tiene serial negativo: Go lo rechaza).
# Claves en secrets/ (no versionado). La CA pública se publica en config/pki/ca.crt para que los clientes la confíen.
set -euo pipefail; cd "$(dirname "$0")/.."; S=secrets/pki; mkdir -p $S config/pki; chmod 700 secrets $S
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
[ -f $S/ca.key ] || openssl req -x509 -newkey rsa:3072 -nodes -keyout $S/ca.key -out $S/ca.crt -days 825 -subj "/CN=Alcaldia Digital Lab CA" 2>/dev/null
cp $S/ca.crt config/pki/ca.crt
for pair in "dc1 10.10.20.10" "dc2 10.20.20.10"; do set -- $pair
  [ -f $S/$1.crt ] || { openssl req -newkey rsa:2048 -nodes -keyout $S/$1.key -out $S/$1.csr -subj "/CN=$1.ad.alcaldia.lab" 2>/dev/null
    printf "subjectAltName=DNS:%s.ad.alcaldia.lab,DNS:%s,DNS:ad.alcaldia.lab,IP:%s\nextendedKeyUsage=serverAuth\n" $1 $1 $2 > $S/$1.ext
    openssl x509 -req -in $S/$1.csr -CA $S/ca.crt -CAkey $S/ca.key -CAcreateserial -out $S/$1.crt -days 825 -extfile $S/$1.ext 2>/dev/null; }
  C="GNS3.$1.$PID"
  docker exec -i $C sh -c 'umask 077; cat > /var/lib/samba/private/tls/key.pem' < $S/$1.key
  docker exec -i $C sh -c 'cat > /var/lib/samba/private/tls/cert.pem' < $S/$1.crt
  docker exec -i $C sh -c 'cat > /var/lib/samba/private/tls/ca.pem' < $S/ca.crt
  docker exec $C sh -c 'grep -q "tls certfile" /etc/samba/smb.conf || sed -i "/^\[global\]/a\\	tls enabled = yes\n\ttls keyfile = tls/key.pem\n\ttls certfile = tls/cert.pem\n\ttls cafile = tls/ca.pem" /etc/samba/smb.conf; pkill samba; sleep 2; samba -D'
  echo "$1: certificado instalado (serial $(openssl x509 -in $S/$1.crt -noout -serial | cut -d= -f2 | cut -c1-12)…)"
done
