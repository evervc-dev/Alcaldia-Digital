# acc/glpi-db: MariaDB 11.4 LTS oficial (BD de GLPI) + espera de credenciales en /etc/acc/db.env + restic (respaldo diario).
FROM mariadb:11.4
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 iputils-ping && rm -rf /var/lib/apt/lists/*
COPY rootfs/ /
COPY --from=restic/restic:0.17.3 /usr/bin/restic /usr/local/bin/restic
RUN chmod +x /opt/acc/*.sh
VOLUME ["/etc/acc"]
ENTRYPOINT []
CMD ["/opt/acc/entrypoint.sh"]
