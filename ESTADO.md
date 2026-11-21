# ESTADO del proyecto

| Campo | Valor |
|---|---|
| Fase actual | **F1 ✅ terminada** → siguiente: **F2 Red Site A** |
| Última actualización | 2026-11-21 ~12:10 (hora local) |
| Plazo | 48 h → 2026-11-23 |
| Proyectos GNS3 abiertos | `ACC-Lab` (id 88f8f32e-4b4f-4e25-9a8b-ac0c9c71c5f9) |
| Nodos encendidos | internet-real (NAT), inet-core, isp1, isp2, atacante-ext (~0.2 GB) |

## Fases
| Fase | Estado |
|---|---|
| F0 Preparación + canario | ✅ |
| F1 Internet simulado | ✅ (docs/pruebas/F1-internet.md) |
| F2 Red Site A | ⏳ siguiente |
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

## Hecho en F1
- Internet simulado con BGP (AS65000/65001/65002), NAT de salida en inet-core (IP fija 192.168.122.10 en virbr0) y CGNAT en los ISP.
- `scripts/deploy-config.sh <proyecto> <nodos>`: aplica `config/nodes/<nodo>/` (interfaces, frr.conf, *.nft…) **escribiendo desde dentro** del contenedor. Después hay que reiniciar el nodo.
- Host: libvirt + red `default` (virbr0) activa; dnsmasq instalado; ufw con `allow in on virbr0` y `route allow in on virbr0`.

## Errores conocidos / gotchas (F1)
- **No usar `docker cp`** para configs: no persisten (GNS3 monta los volúmenes con bind dentro del contenedor).
- `/etc/resolv.conf` lo regenera Docker → el DNS va en `/etc/network/interfaces` (`up printf 'nameserver …' > /etc/resolv.conf`).
- ufw del host bloquea virbr0 si no tiene esas dos reglas.

## Siguiente paso (F2)
Site A: wsw-a1/wsw-a2 (Ethernet switch integrado) en WAN1/WAN2 → fw-a1/fw-a2 (OPNsense, CARP + pfsync en vtnet4) → lagg failover hacia sw-a1/sw-a2 (OVS, trunks VLAN 10–60, LACP entre switches). Pruebas: inter-VLAN, apagar fw-a1 (CARP), bajar WAN1 (gateway group).
