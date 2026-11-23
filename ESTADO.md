# ESTADO del proyecto

| Campo | Valor |
|---|---|
| Fase actual | **F10 ✅ terminada** — MVP completo (F0–F10). Opcional: puesto Windows (defensa), Suricata, GLPI |
| Última actualización | 2026-11-21 ~12:10 (hora local) |
| Plazo | 48 h → 2026-11-23 |
| Proyectos GNS3 abiertos | `ACC-Lab` (id 88f8f32e-4b4f-4e25-9a8b-ac0c9c71c5f9) |
| Nodos encendidos | F1–F3 + dc1, dc2, usr-pc (~5 GB en total) |

## Fases
| Fase | Estado |
|---|---|
| F0 Preparación + canario | ✅ |
| F1 Internet simulado | ✅ (docs/pruebas/F1-internet.md) |
| F2 Red Site A | ✅ (docs/pruebas/F2-site-a.md) |
| F3 Red Site B + WAN | ✅ (docs/pruebas/F3-site-b-wan.md) |
| F4 Servicios base | ✅ (docs/pruebas/F4-servicios-base.md) |
| F5 Servicios críticos (+NAS, escritorios, horario, Cloudflare) | ✅ (docs/pruebas/F5-servicios-criticos.md) |
| F6 Kits de sede | ✅ (docs/pruebas/F6-sedes.md) |
| F7 Publicación Cloudflare | ✅ túneles, DNS, WARP, LAM solo vía WARP (falta: Access para monitor en F8) |
| F8 Monitoreo (mínimo) | ✅ (docs/pruebas/F8-monitoreo.md) |
| F9 Respaldos | ✅ (docs/pruebas/F9-respaldos.md) |
| F10 Pruebas formales | ✅ (docs/pruebas/F10-pruebas-formales.md) |

## Hecho en F0
- Repo con estructura, AGENTS.md, IPAM (`inventory/ipam.md`) y topología (`topology/topologia.md`).
- Host: módulos bonding/openvswitch/8021q cargados y persistentes; busybox estático; `gns3_server.conf` con `ubridge_control_transport = tcp`.
- Imágenes: `acc/router`, `acc/kit-sede`, `acc/pc`, `acc/samba-dc` (1.0) + 12 oficiales con versión fijada; OPNsense 26.7 nano → `~/GNS3/images/QEMU/opnsense-26.7-nano.qcow2`.
- 16 plantillas `ACC-*` en GNS3 (ACC-OPNsense: SATA, consola telnet serie, 1536 MB, 5 NIC virtio).
- Canario: persistencia, bond A/B (también con busybox) y OVS VLAN verificados → `docs/pruebas/F0-canario.md`.

## Errores conocidos / gotchas
- GNS3 3.1 alfa: las plantillas QEMU **necesitan** `hda_disk_interface` o la VM no ve el disco.
- OPNsense ignora el ACPI si no terminó de arrancar → `project close` puede tardar ~2 min.
- OVS (`gns3/openvswitch`): datapath netdev; al arrancar todos los puertos están en `br0` sin VLAN.
- Sin consola en las plantillas Filebrowser, Cloudflared, Mailpit y MinIO (son distroless): se inspeccionan con `docker exec` desde el host.

## Hecho en F1
- Internet simulado con BGP (AS65000/65001/65002), NAT de salida en inet-core (IP fija 192.168.122.10 en virbr0) y CGNAT en los ISP.
- `scripts/deploy-config.sh <proyecto> <nodos>`: aplica `config/nodes/<nodo>/` (interfaces, frr.conf, *.nft…) **escribiendo desde dentro** del contenedor. Después hay que reiniciar el nodo.
- Host: libvirt + red `default` (virbr0) activa; dnsmasq instalado; ufw con `allow in on virbr0` y `route allow in on virbr0`.

## Errores conocidos / gotchas (F1)
- **No usar `docker cp`** para configs: no persisten (GNS3 monta los volúmenes con bind dentro del contenedor).
- `/etc/resolv.conf` lo regenera Docker → el DNS va en `/etc/network/interfaces` (`up printf 'nameserver …' > /etc/resolv.conf`).
- ufw del host bloquea virbr0 si no tiene esas dos reglas.

## Hecho en F2
- fw-a1/fw-a2 configurados con `config/opnsense/site-a.php` (VLAN 10–60, CARP ×8, 2 gateways con monitoreo + killstates, grupo WAN_FAILOVER, reglas por zona, NAT de salida a las VIP, pfsync en vtnet3).
- **Cómo aplicar cambios en OPNsense:** servir `config/opnsense/` con `python3 -m http.server 8088 --bind 192.168.122.1` en el host → en el FW (shell, `exec sh`): `fetch -qo /root/site-a.php http://192.168.122.1:8088/site-a.php && cd /usr/local/opnsense/mvc && php /root/site-a.php a1|a2`. Después reiniciar el FW o recargar el servicio afectado.
- Switches con `config/nodes/sw-a*/ovs.sh` (trunk eth1, LACP isl, acceso eth3 = VLAN 40, libres en VLAN 999, mgmt VLAN 10).
- Pruebas Tier II: falla de FW ≈ 3,1 s, falla de ISP ≈ 4,5 s, pérdida del camino A ≈ 2–3 s.

## Errores conocidos / gotchas (F2)
- Root de OPNsense con la contraseña por defecto (`opnsense`): **pendiente** cambiarla (valor en `.env`, `OPNSENSE_ROOT_PASS`).
- La shell de root de OPNsense es csh: hacer siempre `exec sh` antes de comandos con redirecciones o comillas.
- Si fw-a1 arranca como BACKUP: revisar `sysctl net.inet.carp.demotion` (pfsync) y corregir con `=-240`.
- OVS: ojo al asignar puertos de servidores (eth4–13 → VLAN de su zona en **ambos** switches).

## Hecho en F3
- fw-b (`site-b.php`) y WAN A↔B (`wan-ab.inc.php`): 2 túneles IPsec VTI (ISP1 coste 10 / ISP2 coste 20) + OSPF (os-frr instalado en los 3 FW).
- **Acceso de administración por SSH con clave** (`secrets/acc_admin_ed25519`, fuera de git; la pública se instala con `set-root-key.php`). Ejecutar en un FW: `bash scripts/fw.sh fw-a1|fw-a2|fw-a|fw-b '<comandos sh>'` (salta por adm-pc / adm-pc-b).
- Contraseña de root desde `.env` (`scripts/opnsense-root-hash.sh` + `set-root-pass.php`): la de fábrica ya no sirve. **La consola serie pide esa contraseña: usar SSH.**
- Reaplicar config de un FW (idempotente): regenerar `config/opnsense/ipsec.psk` desde `.env` (el FW lo borra al leerlo) y luego `bash scripts/fw.sh fw-b "B=http://192.168.122.1:8088; for f in site-b.php wan-ab.inc.php ipsec.psk; do fetch -qo /root/\$f \$B/\$f; done; cd /usr/local/opnsense/mvc && php /root/site-b.php; configctl filter reload"`. Requiere el servidor HTTP del host (`python3 -m http.server 8088 --bind 192.168.122.1` en `config/opnsense/`).

## Errores conocidos / gotchas (F3)
- Ver docs/pruebas/F3-site-b-wan.md (5 errores de OPNsense 26.7 con IPsec/OSPF y su solución).
- Failover de fw-a1 con túneles: ≈ 36 s hasta recuperar A↔B (DPD). Aceptable; mejora: DPD 2 s/6 s.

## Hecho en F4
- AD `ad.alcaldia.lab`: dc1 (A) + dc2 (B) con réplica DRS (2,2 s) y DNS secundario. Ejemplo: `docker exec GNS3.dc1.<pid> samba-tool user list`.
- DHCP en OPNsense (`dhcp.inc.php`), rangos repartidos entre fw-a1 y fw-a2.
- **Aplicar config a un OPNsense:** `bash scripts/opn-apply.sh fw-a1|fw-a2|fw-b [filter dnsmasq strongswan frr dpinger]` (necesita el servidor HTTP del host en :8088).
- Secretos de servicios generados en `.env` con `scripts/gen-secrets.sh` (solo rellena los vacíos).

## Errores conocidos / gotchas (F4)
- Cambiar la imagen Docker de un nodo exige **recrear el nodo** (borrar + crear + volver a enlazar + deploy-config), porque restart no basta.
- El comprobador de seguridad bloquea `rm` dentro de `sh -c`: usar `mv` o borrar desde el host.

## Hecho en F5 (ver docs/pruebas/F5-servicios-criticos.md)
- NAS A/B inmutables con réplica; ts1 con escritorios por RDP; horario por política de grupo con mensaje (RDP y web); portal, archivo y Authelia publicados por Cloudflare; Site B en espera con réplica horaria de la BD y `dr-dns-switch.sh`.
- Scripts nuevos: ad-setup.sh, ad-tls.sh, nas-setup.sh, cf-setup.sh, services-setup.sh (SITE=A|B), archivo-setup.sh [nodo], dr-dns-switch.sh, gen-if.py.

## Incidente al abrir la GUI (21/11 ~16:05) — resuelto
- Al conectarse la GUI, GNS3 rehízo los switches integrados WAN (`wsw-a1/wsw-a2`, bridges Linux del host) y falló (`brctl vlan_add ... Invalid argument`): el puerto del ISP quedó fuera del bridge → **Site A sin Internet**. Arreglo inmediato con sudo (usuario) y **sustitución definitiva de wsw-a1/wsw-a2 por ACC-OVS** (ya no quedan switches integrados).
- Tras el corte, cloudflared-a quedó con conexiones muertas (502) → reinicio del nodo.
- Nuevo: `scripts/lab-check.sh` (chequeo de salud) y `docs/OPERACION.md` (apagar/encender). Envoltorios con reintento (authelia, nginx, cloudflared, portal, gate) para el arranque en frío.

## Pendientes que arrastra F5
1. ~~WARP~~ ✅ hecho (cf-zt-setup.sh) + gestión de identidades por LAM vía WARP (docs/pruebas/F5b-gestion-identidades.md).
2. ~~TOTP de extremo a extremo~~ ✅ validado por el usuario.
3. Respaldos restic (homes de ts1, archivo, volcados del portal) → nas-a → nas-b: **F9**.
4. ts1 usa una imagen anterior (sin el arreglo de PID ni zenity de serie): están aplicados dentro del contenedor y en la imagen; si se recrea, hay que volver a unirlo (`net ads join`).

**Puertos de sw-a1/sw-a2:** eth8 y eth10 tienen enlaces fantasma (no usar). Libres: eth0, eth2, eth21–eth23 (y eth5/eth18 en sw-a2). sw-b1 libres: eth0, eth2, eth13, eth14.

## Hecho en F6
- **Puesto unido al dominio:** `puesto-01` (Debian 13 XFCE, LightDM, consola VNC) en la Sede 1: login con cuentas del AD y horario aplicado. Guía para el puesto Windows de la defensa: `docs/PUESTO-WINDOWS.md`.
- 3 sedes con kit replicable (`new-sede.sh N` → `sede-setup.sh N`), túneles A-WAN1/A-WAN2/B con OSPF, pool CGNAT por sede, hub-and-spoke probado y failover sede→A-WAN2→B. `lab-check.sh` incluye las sedes.
- Para añadir una sede N: `new-sede.sh N`, añadir su IP pública a `SEDES_PUB` (wan-ab.inc.php) y al snat del ISP, `opn-apply.sh` en los 3 FW, `ad-ou-delegacion.sh N`, crear nodos y `sede-setup.sh N`.

## (anterior) Siguiente paso (F6)
Kits de 3 sedes: kit-sede-0N (acc/kit-sede) en el CGNAT de su ISP (sede 1 y 3 → isp1 eth3/eth4; sede 2 → isp2 eth3) + switch integrado + 2 PC (una de ellas puede ser un pc-gui). Túneles IPsec salientes: 2 al Site A (VIP WAN1/WAN2) y 1 al Site B, OSPF con costes 10/20/100. Usuarios del AD por sede (`ad-setup.sh usuario …`). Pruebas: portal/archivo/RDP desde la sede, aislamiento sede↔sede, caída de túnel.

## Gestión de identidades (hecho)
- Altas, bajas y resets de funcionarios: **LAM** en `https://lam.evervc.dev` (solo con WARP + MFA + cuenta AD de `gestores-identidad`). Por terminal: `scripts/ad-setup.sh usuario <u> funcionarios "<Nombre>"` (luego moverlo a su OU de sede).
- Certificado de lam.evervc.dev: Let's Encrypt, vence 19/02/2027 → renovar con `scripts/cert-lam.sh` + `scripts/lam-publish.sh`.

## (anterior) Siguiente paso (F8)
Zabbix: zbx-db (acc/pg), zbx-server y zbx-web (oficiales) en SERVIDORES A; agentes/SNMP en FW (os-net-snmp), switches, kits y servicios; mapa de red A/B/sedes; disparadores de la Tabla 13 aplicables (enlace/túnel caído, servicio caído, NAS > 80 %, réplica atrasada > RPO); alertas por correo a mailpit; `monitor.evervc.dev` protegido con Cloudflare Access (o solo por WARP).

## Hecho en F8 (ver docs/pruebas/F8-monitoreo.md)
- zbx-db/zbx-server/zbx-web (10.10.20.34/.30/.33) en SERVIDORES A con doble enlace (sw-a1/sw-a2 eth22, eth23, eth2). Configuración por API: `scripts/zbx-setup.sh` (idempotente; re-ejecutar tras cambios).
- 35 hosts, servicios, túneles (desde el CD + SNMP de los kits), réplica (ODBC), NAS (%), portal público; alertas a mailpit; mapa «Alcaldía Digital».
- `monitor.evervc.dev`: Cloudflare Access (WARP_EMAILS, PIN) + login Zabbix. `cf-zt-setup.sh` paso 6 y `cf-setup.sh` (HOSTS incluye monitor).
- Puesto unido al dominio `puesto-01` (Sede 1) y `PUERTOS_AD_CLIENTE` (ver F6).

## Errores conocidos / gotchas (F8)
- Al reabrir el proyecto: zbx.env/pg.env están en volúmenes; si Zabbix no arranca, `services-setup.sh` y reiniciar los 3 nodos.
- Para probar un corte de sede NO usar `ip link set eth0 down` sin luego `ip route replace default via 100.64.N.1` (el kernel borra la ruta por defecto).
- Si se mata charon en un kit con imagen antigua: `swanctl --load-all` (la imagen nueva ya lo hace sola).
- Zabbix 7 dibuja los mapas en el navegador (map.php devuelve JSON): la captura del mapa se hace desde monitor.evervc.dev.

## (anterior) Siguiente paso (F9)
restic: homes de ts1, archivo y dumps del portal → nas-a (bucket con Object Lock), replicado a nas-b; `scripts/backup-configs.sh` (config.xml de OPNsense, OVS, FRR, swanctl) → `configs/` en git; cinta LTO simulada (contenedor `tape` detenido); alerta en Zabbix si el último respaldo tiene > 26 h.

## Incidente tras reiniciar el PC (22/11 ~21:30 local) — resuelto
`lab-check` dio 7 fallos. Causas y arreglos permanentes:
1. **Tunables `net.enc.*.ipsec_filter_mask=0` nunca se habían guardado:** en OPNsense 26.7 son entradas *estáticas* del modelo (clave md5) que no se serializan. Solo valían en caliente y al reiniciar volvieron a 2/1, así que enc0 descartaba el tráfico A↔B (OSPF seguía Full, pero sin datos). Arreglo en `wan-ab.inc.php`: crear una entrada propia (uuid). Verificado reiniciando fw-b: ahora persiste.
2. **Sedes con 1 túnel:** los kits arrancan antes que fw-a y reciben `NO_PROPOSAL_CHOSEN`, ante el que strongSwan no reintenta. Arreglo: `/opt/acc/vigia-tuneles.sh` en la imagen del kit relanza cada 30 s lo que no esté ESTABLISHED.
3. **Réplica del portal > RPO** tras el corte: ahora `acc/pg` reintenta a los 5 min si la copia falla. Copia manual: el bucle de `images/pg/rootfs/opt/acc/entrypoint.sh` ejecutado a mano en portal-db-b.
4. **Réplica AD con fallos acumulados:** `docker exec -e AP=... GNS3.dc2.<id> samba-tool drs replicate dc2 dc1 <NC> -U "administrator%$AP"` para los 5 NC (DomainDnsZones, ForestDnsZones, dominio, Configuration, Schema).
- Gotcha: no usar `pkill -f "http.server 8088"` desde un `bash -c` que contenga esa cadena (se mata a sí mismo, exit 144).

## Hecho en F9 (ver docs/pruebas/F9-respaldos.md)
- restic diario 02:00 (ts1 /home, archivo, portal-db pg_dumpall, dc1 domain backup) → nas-a `respaldos/repo`, **COMPLIANCE 7 d**, replicado a nas-b (sin `delete`); mantenimiento en nas-a 04:00. Cinta `tape` (10.20.60.20, sw-b1 eth13) **apagada**; encenderla graba un cartucho.
- Scripts: `nas-setup.sh` (re-ejecutable) → `respaldo-setup.sh [ahora]`; `backup-configs.sh` → `configs/` (saneado) + NAS (completo). Zabbix: antigüedad del respaldo; lab-check: sección Respaldos.
- Secretos nuevos en .env: RESTIC_PASSWORD (¡sin ella no se restaura nada!), RESTIC_S3_KEY, RESTIC_RO_KEY. MINIO_ROOT_PASS rotada.

## Errores conocidos / gotchas (F9)
- Repositorio roto de la primera prueba en `respaldos/restic` (GOVERNANCE): se puede retirar con la cuenta admin: `mc rm -r --versions --force --bypass a/respaldos/restic` (y `b/`). No afecta a `respaldos/repo`.
- Con COMPLIANCE nada del bucket se puede borrar antes de 7 días (por diseño).
- `pkill -f` dentro de `sh -c`: usar el truco `[r]espaldo.sh` para no matarse a sí mismo.
- Los alias `mc` de los NAS no persisten (contenedor recreado): `nas-setup.sh` los vuelve a crear.

## (anterior) Siguiente paso (F10)
Pruebas formales T1–T13 con evidencias: failover Tier II (ya medido, re-documentar), **T8 DR completo del Site A** (dr-dns-switch.sh B, arrancar portal-b/authelia-b/gate-b/archivo-b, restaurar archivo desde nas-b, medir RTO), T5 hacking (nmap, hydra contra Authelia/SSH, aislamiento lateral), energía (camino A/B).

## Hecho en F10 (ver docs/pruebas/F10-pruebas-formales.md y docs/PROCEDIMIENTOS-DR.md)
- T1–T8 ejecutadas con sonda de extremo a extremo (`f10-sonda.sh`); T9 documentada. Scripts: `test-zones.sh`, `dr-activar-b.sh`, `dr-retorno-a.sh`.
- Correcciones nacidas de las pruebas: SSH solo clave + SSH/GUI solo GESTION/ADMIN; kits descartan gestión/ADMIN/DMZ/RESPALDO/IP de FW; cloudflared QUIC; DPD 5 s en kits; anuncio de MAC de gestión en switches; Zabbix vigila los FW por su IP de ADMIN.

## Errores conocidos / gotchas (F10)
- **pf no evalúa** el tráfico que llega por una VTI con destino al propio firewall (ni con regla explícita): la protección está en el kit de la sede (nft) y en SSH/GUI restringidos.
- SSH a los firewalls: **solo con clave** (`fw.sh` desde adm-pc / adm-pc-b). GUI solo desde GESTION/ADMIN (`https://10.10.40.2`, `.3`, `10.20.40.1`).
- Al conmutar DNS (DR) Cloudflare tarda 1–2 min en propagar: respuestas mixtas durante ese tiempo.
- Durante un DR, `portal-db-b` tiene `/etc/acc/DR-ACTIVO`: no se pisa con la réplica. El retorno la retira; reiniciar el nodo.
- Para pruebas con `ip link set ethX down` en los ISP basta `ip link set ethX up` (rutas conectadas); en los kits hay que restaurar la ruta por defecto.

## Extras tras F10 (22/11)
- **Tareas programadas** (`scripts/tareas.sh`, temporizador `acc-tareas.timer` de systemd --user; instalar: `scripts/tareas-instalar.sh`):
  respaldo de configuraciones cada 24 h (+ commit local de `configs/`) y cinta cada 7 días (enciende `tape` por la API de GNS3, graba y lo apaga).
  Resultado a Zabbix (host `tareas-programadas`, trapper `acc.tarea[configs|cinta]`): alerta si falla o si no hay dato en 26 h / 8 d.
- Gotchas: los OPNsense son QEMU (no aparecen en `docker inspect`); la cinta graba **al arrancar** el nodo, así que si `tape` quedó encendido la tarea lo apaga y lo vuelve a encender.
  Las tareas corren mientras la sesión del usuario está abierta (sin *linger*); si el lab está apagado se reintenta cada hora.
- **Incidente 22/11 (arranque en frío):** A↔B estuvo caído desde las 08:26 hasta las 11:45. fw-b arrancó antes que fw-a1, recibió `NO_PROPOSAL_CHOSEN` y strongSwan no reintenta ese error (mismo caso que los kits).
  Arreglo: **vigía en fw-b** (`acc_vigia_ipsec()` en `wan-ab.inc.php`): `/usr/local/sbin/acc-vigia-ipsec.sh` + acción configd `acc vigia-ipsec` + cron de OPNsense cada minuto (lo ejecuta como `nobody`, vía configd).
  Probado terminando el túnel ISP1: relanzado en 60 s (`grep acc-vigia /var/log/system/latest.log`).
- **Zabbix «no se puede comprobar el respaldo» tras reiniciar el PC:** el enlace `/usr/lib/zabbix/externalscripts/restic-ultimo.sh` se perdía al recrearse el contenedor (el script está en el volumen `/etc/acc`). Ahora lo crea el `entrypoint` de `acc/zabbix-*` al arrancar (imagen reconstruida).

## Hecho: mesa de servicio GLPI (ver docs/pruebas/F11-mesa-servicio.md)
- Nodos `glpi` (10.10.20.31) y `glpi-db` (10.10.20.35); `mesa.evervc.dev` con Authelia + horario + SSO `Remote-User`; perfiles por grupo AD (`mesa-tecnicos`, `mesa-admins`); Zabbix abre/resuelve tickets (webhook); respaldos diarios.
- Reconstruir: `build-images.sh` → `gns3-templates.sh` → crear nodos + enlaces (glpi: sw-a1 eth0 / sw-a2 eth0; glpi-db: sw-a1 eth8 / sw-a2 eth5) → `deploy-config.sh ACC-Lab glpi glpi-db sw-a1 sw-a2 nginx-dmz` → `gen-secrets.sh` → `services-setup.sh` → reiniciar glpi/glpi-db/authelia → `glpi-setup.sh` → `zbx-setup.sh` → `respaldo-setup.sh` → `cf-setup.sh`.

## Errores conocidos / gotchas (GLPI)
- **No cambiar propiedades de un nodo Docker cuya imagen se reconstruyó** (p. ej. `environment`): GNS3 borró el contenedor y el nodo quedó inservible. Recrear el nodo.
- La cuenta `zabbix` de GLPI debe tener **solo** Technician como perfil por defecto (si no, la API entra como Self-Service y no puede resolver).
- `glpi-setup.sh` no cambia contraseñas ya puestas (GLPI rechaza reutilizarlas). Para rotar `GLPI_ZABBIX_PASS`: cambiarla en GLPI, en `.env` y volver a ejecutar `zbx-setup.sh` (macro secreta).
- GLPI no está en el DR (como Zabbix y LAM): `mesa.evervc.dev` no se mueve al Site B; se restaura desde los respaldos si hiciera falta.
- **Tras reabrir el proyecto (22/11 noche):** `lab-check` marcaba «Object Lock» en nas-a (el bucket estaba bien: faltaban los alias `a`/`b` de `mc`, que se pierden al recrear el contenedor) y `tape` encendido por *Start all*. Arreglos: el `entrypoint` de `acc/nas` crea los alias al arrancar (imagen reconstruida; entra al reabrir el proyecto) y `tareas.sh` apaga `tape` en cuanto termina el cartucho de su arranque.

## Hecho: IDS/IPS Suricata (ver docs/pruebas/F12-ids-ips.md)
- Suricata (IDS, ET Open) en WAN1/WAN2 de fw-a1, fw-a2 y fw-b + respuesta activa (tabla `ACC_IDS_BLOQUEO`, 1 h) + Zabbix + ticket GLPI. Aplicar: `opn-apply.sh <fw> filter ids` (con el servidor HTTP del host).
- Gotchas: `template reload OPNsense/IDS` antes de `ids restart`; un único `actions_acc.conf` (el cron cachea las acciones). Tras una prueba de nmap, el atacante queda bloqueado 1 h: `pfctl -t ACC_IDS_BLOQUEO -T flush` en el FW para repetir.

## Hecho: coherencia con las Fases (22/11 noche)
- Horario 07:00–19:00; archivo, glpi y glpi-db cada 4 h (RPO 4 h) y al arrancar; retención 24 h + 30 diarias + 4 semanales + 12 mensuales; zbx-db en el respaldo diario; advertencias también abren ticket.
- **Reporte ciudadano** (`portal.evervc.dev/reportar`) → ticket P4 en GLPI (cuenta `portal`, Self-Service; `GLPI_PORTAL_PASS`). Self-Service no puede listar categorías: `services-setup.sh` pasa `GLPI_CATEGORIA_ID` al portal. Pendientes reintentados cada 5 min. El portal vive en el contenedor recreado al reabrir: la imagen `acc/portal:1.0` ya trae el código.
- **GLPI: catálogo, calendario y SLA** (`glpi-setup.sh`): categorías S1–S6 + solicitudes estándar, SLA P1–P4 por reglas. Gotchas: el criterio *prioridad* de las reglas no admite regex (una regla por valor); PHP del contenedor en UTC → `zz-acc-tz.ini`; `database:enable_timezones` + `GRANT SELECT ON mysql.time_zone_name`.
- **SLA de Zabbix** (S1–S6, Tabla 4): etiqueta `servicio=Sx` en los disparadores de disponibilidad; informe `scripts/sla-informe.sh`. Gotcha: `algorithm` 1 = «si todos los hijos», 2 = «el más grave».
- **Sala simulada** (`scripts/sensores.py`, servicio `acc-sensores`): UPS/generador/ambiente de la Fase 3 → Zabbix (`sala-a`, `sala-b`) con los umbrales de la Tabla 13 y escenarios inyectables. Estado: `~/.local/state/acc/sensores-*.json`.
- **T10 carga** (`prueba-carga.py`) y **T11 restauración de configuración** (`restaurar-config.sh`, fuera de banda por GESTION con `GESTION=1 fw.sh`). Gotchas: `rc.reload_all` tarda minutos; los contenidos grandes van por la entrada estándar (`fw.sh <fw> -`).
- **Entrega** (`scripts/exportar-entrega.sh` → `../entrega/`, fuera de git): topología portátil sin volúmenes (20 KB, guardia de secretos), diagrama, configs, pruebas, `IMAGENES.md`. La copia completa de GNS3 exige el proyecto detenido: `--solo-completo` al apagar. Lienzo reordenado (zbx-*/glpi* dentro del Site A, lam movido, recuadro A 840×935). Gotchas: el MCP `drawing list` falla (pydantic) y `update` exige el UUID completo; el PNG del MCP no dibuja textos → `topology/topologia.png` con `rsvg-convert`.

## 23/11: suplantación por Remote-User (cerrada) y bucles de respaldo
- `PROXY_SECRET` (portal) y `ARCHIVO_HEADER_ID` (filebrowser) en `.env`; `services-setup.sh` los entrega a nginx (`conf.d/certs/*-auth.inc`). Cambiar el del archivo exige el nodo DETENIDO y `archivo-setup.sh archivo` (y `archivo-b`).
- USUARIOS solo tiene DNS/AD/RDP hacia servidores. El IDS solo bloquea escaneos/exploits/DoS contra las WAN y nunca a Cloudflare.
- No escribir horas con cero delante en aritmética de shell (`08` = octal inválido).

## 23/11: roles (4 niveles) y accesos de emergencia — ver docs/ROLES-Y-ACCESOS.md
- `horario.conf` ya NO manda: la política está en el AD y se edita en `lam.evervc.dev/accesos`.
- Gotchas: no usar `pkill -f gate.py` (mata también el bucle de arranque): `kill $(pidof python3)`. Zabbix usa LDAP; el grupo «Zabbix administrators» sigue con autenticación interna (rescate).
- **OPNsense con AD** (`opn-ldap.sh`). `backup-configs.sh` tapa `ldap_bindpw` y quita de `configs/` los usuarios que crea el login (datos personales).
- **MAC duplicada (causa de caídas intermitentes tras encender):** el host podía pisar la MAC de `eth0` con una repetida (mailpit, portal-db y nas-a). `interfaces` fija la de Docker (`02:42…`) en bond0.
- **Cinta «nas-b no responde» al encender todo (arreglado 23/11):** `cinta.sh` hacía `mc alias set` una sola vez; si la red aún no subía, no se guardaba y fallaba los 10 min. Ahora va dentro del bucle (reproducido con la red caída 30 s: el viejo no se recupera, el nuevo graba a los 32 s). Entra al reabrir el proyecto (imagen `acc/nas`).
- Authelia envía los códigos por correo real (`SMTP_*` en `.env`); `codigo-mfa.sh` solo sirve con mailpit.
