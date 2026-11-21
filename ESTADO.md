# ESTADO del proyecto

| Campo | Valor |
|---|---|
| Fase actual | **F0 ✅ terminada** → siguiente: **F1 Internet simulado** |
| Última actualización | 2026-11-21 ~12:10 (hora local) |
| Plazo | 48 h → 2026-11-23 |
| Proyectos GNS3 abiertos | ninguno (`ACC-Canario` borrado tras la prueba) |
| Nodos encendidos | ninguno |

## Fases
| Fase | Estado |
|---|---|
| F0 Preparación + canario | ✅ |
| F1 Internet simulado | ⏳ siguiente |
| F2 Red Site A | ⏳ |
| F3 Red Site B + WAN | ⏳ |
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

## Siguiente paso (F1)
Crear el proyecto `ACC-Lab` con inet-core (+ nodo NAT), isp1, isp2 y atacante-ext; FRR/BGP entre ISPs; NAT masquerade en inet-core; CGNAT en ISPs. Prueba: `ping 1.1.1.1` y `curl https://cloudflare.com` desde los ISP.
