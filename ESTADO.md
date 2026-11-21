# ESTADO del proyecto

| Campo | Valor |
|---|---|
| Fase actual | **F2 ✅ terminada** → siguiente: **F3 Site B + WAN (IPsec VTI + OSPF)** |
| Última actualización | 2026-11-21 ~12:10 (hora local) |
| Plazo | 48 h → 2026-11-23 |
| Proyectos GNS3 abiertos | `ACC-Lab` (id 88f8f32e-4b4f-4e25-9a8b-ac0c9c71c5f9) |
| Nodos encendidos | F1 + wsw-a1/2, fw-a1/fw-a2 (OPNsense 1.5 GB c/u), sw-a1/sw-a2, adm-pc (~3.5 GB en total) |

## Fases
| Fase | Estado |
|---|---|
| F0 Preparación + canario | ✅ |
| F1 Internet simulado | ✅ (docs/pruebas/F1-internet.md) |
| F2 Red Site A | ✅ (docs/pruebas/F2-site-a.md) |
| F3 Red Site B + WAN | ⏳ siguiente |
| F4 Servicios base | ⏳ |
| F5 Servicios críticos | ⏳ |
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

## Siguiente paso (F3)
Site B: fw-b (OPNsense, WAN1 203.0.113.10/30, WAN2 198.51.100.10/30, trunk → sw-b1) + sw-b1/sw-b2. IPsec VTI A↔B por ISP1 y por ISP2 + OSPF (os-frr). **Plan B inmediato** si CARP + VTI falla: túneles a la IP propia de cada FW.
