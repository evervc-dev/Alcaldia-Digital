# ESTADO del proyecto

| Campo | Valor |
|---|---|
| Fase actual | **F5 🔄 EN CURSO (pausada 21/11 ~14:45)** — ver «Retomar F5» abajo |
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
| F5 Servicios críticos (+NAS, escritorios, horario, Cloudflare) | 🔄 en curso |
| F6 Kits de sede | ⏳ |
| F7 Publicación Cloudflare | ⏳ |
| F8 Monitoreo (mínimo) | ⏳ |
| F9 Respaldos | ⏳ |
| F10 Pruebas | ⏳ |

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

## Retomar F5 (estado al pausar)
**Hecho y probado**
- AD: grupos `funcionarios` (logonHours lun–vie 8:00–16:00 = 14–22 UTC), `acceso-24h`, `nas-admins`; `svc-lectura`; usuarios demo ana.funcionaria / tecnico.soporte / admin.dc (`scripts/ad-setup.sh`). El DC rechaza fuera de horario con `NT_STATUS_INVALID_LOGON_HOURS` (también en LDAP: data 530).
- CA del laboratorio y certificados LDAPS válidos en dc1/dc2 (`scripts/ad-tls.sh`; CA pública en `config/pki/ca.crt`, claves en `secrets/pki/`).
- NAS: nas-a (10.10.60.10, bond) y nas-b (10.20.60.10) con MinIO, bucket `respaldos` con Object Lock GOVERNANCE 7d, réplica A→B y login AD (`nas-admins` → consoleAdmin) (`scripts/nas-setup.sh env|config`). Borrado bloqueado y réplica verificados.
- ts1 (10.10.20.40, bond): XFCE + xrdp 0.10, unido al dominio (winbind), home `/home/ALCALDIA/<u>`; `wbinfo --pam-logon` devuelve el motivo del horario. xrdp escucha en :3389.
- Switches sw-a1/sw-a2 ampliados a 24 puertos (ver incidente en la bitácora).
- Cloudflare: túneles `acc-site-a` / `acc-site-b` + ingress + DNS `portal|archivo|auth.evervc.dev` → túnel A (`scripts/cf-setup.sh`). **cloudflared-a conectado** (4 conexiones). Zero Trust activado por el usuario: team `alcaldia-digital`.
- Nodos web creados y con red (bond, Internet OK): cloudflared-a .30.11, authelia .20.11, gate .20.13, portal .20.20, portal-db .20.22, archivo .20.21, mailpit .20.32, nginx-dmz .30.10 (sw eth20), pc-gui (VLAN 50, sw-a1 eth18).

**Pendiente inmediato (en este orden)**
1. Reiniciar `nginx-dmz`, `portal-db`, `authelia` y `portal` (gns3-mcp) y verificar: `nginx -t`; postgres «ready to accept» (PGDATA=…/data/pgdata ya en pg.env); log de Authelia sin errores LDAP/SMTP (`/config/authelia.log`).
2. Configurar filebrowser (archivo): `filebrowser config set --auth.method=proxy --auth.header=Remote-User` + `createUserDir` (carpeta personal por usuario) y reiniciar.
3. Probar de extremo a extremo desde fuera: `https://portal.evervc.dev`, `/funcionarios` → Authelia → TOTP (código en mailpit :8025) → bandeja; archivo; ana.funcionaria fuera de horario → texto personalizado; sesión vigente fuera de horario → página de horario-gate.
4. pc-gui: arrancar (consola VNC; el host ya tiene Xvfb/x11vnc/tigervnc) → RDP a ts1 → comprobar que **la pantalla de xrdp muestra el motivo del horario** (si no: plan B pamerrortxt / mensaje PAM propio).
5. ts1: la imagen corrige los PID obsoletos de xrdp, pero el nodo usa la imagen anterior → si se recrea hay que volver a unirlo (`net ads join`).
6. Access (team alcaldia-digital): políticas para archivo/monitor y WARP con rutas privadas 10.10.0.0/16 y 10.20.0.0/16 (el token debe incluir Access: Apps and Policies + Zero Trust).
7. Réplicas al Site B: portal-db-b, archivo-b, nginx-dmz-b, cloudflared-b; pg_dump/WAL horaria; archivo cada 4 h; restic de /home ts1 y del archivo a nas-a.
8. Actualizar PLAN (sección escritorios/horario/NAS), IPAM, topología y lienzo; cerrar F5 con docs/pruebas/F5-*.md.

**Puertos de sw-a1/sw-a2:** eth8 y eth10 quedaron ocupados por enlaces fantasma (no usarlos). Libres: eth0, eth2, eth21–eth23 (y eth5/eth18 en sw-a2).
