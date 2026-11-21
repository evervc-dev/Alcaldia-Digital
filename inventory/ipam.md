# IPAM — fuente única de direccionamiento

> Copiado de PLAN_DESARROLLO.md §4 el 2026-11-21. A partir de ahora **este archivo manda**: si cambia algo, se cambia aquí primero.


### 4.1 Bloques globales

| Bloque | Uso |
|---|---|
| 10.10.0.0/16 | Site A |
| 10.20.0.0/16 | Site B |
| 10.100.N.0/24 | Sede N (N = 1..255; 139 hoy, 190 en el escenario de crecimiento) |
| 172.16.0.0/16 | Túneles VTI (/30) |
| 203.0.113.0/24 | "Públicas" de ISP1 (rango de documentación) |
| 198.51.100.0/24 | "Públicas" de ISP2 |
| 192.0.2.0/24 | Tránsito inet-core ↔ ISP (/30) |
| 100.64.0.0/16 | CGNAT de sedes (ISP hace NAT → túneles salientes con NAT-T) |
| 192.168.122.0/24 | Red del nodo NAT de GNS3 (salida real) |

### 4.2 VLANs (idénticas en A y B: 10.X0.<VLAN>.0/24, X=1 A, X=2 B)

| VLAN | Nombre | Site A | Site B | Gateway (VIP CARP en A) | Contenido |
|---|---|---|---|---|---|
| 10 | GESTION | 10.10.10.0/24 | 10.20.10.0/24 | .1 (FW-A1 .2, FW-A2 .3) | IP de gestión de switches, oxidized, syslog |
| 20 | SERVIDORES | 10.10.20.0/24 | 10.20.20.0/24 | .1 | dc, authelia, portal, archivo, zabbix, glpi |
| 30 | DMZ | 10.10.30.0/24 | 10.20.30.0/24 | .1 | nginx-dmz, cloudflared |
| 40 | ADMINISTRACION | 10.10.40.0/24 | 10.20.40.0/24 | .1 | Personal del centro (DHCP) |
| 50 | USUARIOS | 10.10.50.0/24 | — | .1 | Usuarios internos / pruebas (DHCP) |
| 60 | RESPALDO | 10.10.60.0/24 | 10.20.60.0/24 | .1 | nas-a/nas-b, tape |
| 99 | HA-PFSYNC | 10.10.99.0/29 (enlace directo, sin switch) | — | — | FW-A1 .1, FW-A2 .2 |

En las sedes: LAN 10.100.N.0/24, GW .1 (kit), DHCP .100–.199; `pc-0N-a` → .100 y `pc-0N-b` → .101 (reserva DHCP por MAC).

### 4.3 Direcciones de servidores (Site A → Site B espejo en 10.20.x)

| Host | IP A | IP B |
|---|---|---|
| dc1 / dc2 (DNS) | 10.10.20.10 | 10.20.20.10 |
| authelia + redis | 10.10.20.11 | — (se arranca en B en DR) |
| portal | 10.10.20.20 | 10.20.20.20* |
| portal-db | 10.10.20.22 | 10.20.20.22 (réplica) |
| archivo | 10.10.20.21 | 10.20.20.21 |
| zbx-server / zbx-web / zbx-db | 10.10.20.30 / .33 / .34 | — (respaldo diario de la BD a nas-b) |
| glpi (opcional) | 10.10.20.31 | — |
| mailpit | 10.10.20.32 | — |
| nginx-dmz | 10.10.30.10 | 10.20.30.10 |
| cloudflared | 10.10.30.11 | 10.20.30.11 |
| syslog | 10.10.10.21 | — |
| SW-A1 / SW-A2 gestión | 10.10.10.11 / .12 | SW-B1/B2 10.20.10.11 / .12 |
| nas-a / nas-b | 10.10.60.10 | 10.20.60.10 |
| tape | — | 10.20.60.20 |

DHCP: Kea en OPNsense (VLAN 40/50 en A y en B); en sedes, dnsmasq del kit. DNS: dc1 primario, dc2 secundario (RQ-13); dominio AD `ad.alcaldia.lab`; zona pública en Cloudflare `evervc.dev`.

### 4.4 Enlaces punto a punto y WAN

| Enlace | Subred | Extremos |
|---|---|---|
| inet-core ↔ ISP1 | 192.0.2.0/30 | .1 core / .2 ISP1 |
| inet-core ↔ ISP2 | 192.0.2.4/30 | .5 core / .6 ISP2 |
| inet-core ↔ NAT GNS3 | DHCP 192.168.122.x | salida real |
| ISP1 ↔ Site A (WAN1) | 203.0.113.0/29 | .1 ISP1, .2 FW-A1, .3 FW-A2, **.4 VIP CARP** |
| ISP2 ↔ Site A (WAN2) | 198.51.100.0/29 | .1 ISP2, .2 FW-A1, .3 FW-A2, **.4 VIP CARP** |
| ISP1 ↔ Site B (WAN1) | 203.0.113.8/30 | .9 ISP1, .10 FW-B |
| PFSYNC A | 10.10.99.0/29 | .1 fw-a1, .2 fw-a2 (también router-id OSPF) |
| ISP2 ↔ Site B (WAN2) | 198.51.100.8/30 | .9 ISP2, .10 FW-B |
| ISP1 ↔ sede 1 / sede 3 | 100.64.1.0/30, 100.64.3.0/30 | .1 ISP, .2 kit (CGNAT) |
| ISP2 ↔ sede 2 | 100.64.2.0/30 | .1 ISP, .2 kit (CGNAT) |
| VTI A↔B por ISP1 / ISP2 | 172.16.0.0/30, 172.16.0.4/30 | .1/.5 A (ipsec1/ipsec2 = opt8/opt9), .2/.6 B; IKE entre VIP A (203.0.113.4 / 198.51.100.4) y B (.10) |
| VTI sede N → A (WAN1) | 172.16.N.0/30 | .1 A, .2 kit |
| VTI sede N → A (WAN2) | 172.16.N.4/30 | .5 A, .6 kit |
| VTI sede N → B | 172.16.N.8/30 | .9 B, .10 kit |

OSPF área 0 sobre VTI: costo 10 (A por WAN1), 20 (A por WAN2), 100 (B). Las sedes no se ven entre sí (filtrado en A y B, hub-and-spoke).

### 4.5 Matriz de filtrado entre zonas (resumen)

| Origen \ Destino | SERVIDORES | DMZ | GESTION | ADMIN | Sedes | Internet |
|---|---|---|---|---|---|---|
| Internet | ✗ | solo vía Cloudflare Tunnel (no hay puertos abiertos) | ✗ | ✗ | ✗ | — |
| DMZ | portal:8000, archivo:8080, authelia:9091 | — | ✗ | ✗ | ✗ | 443/7844 (cloudflared) |
| Sedes | LDAP/DNS/HTTPS a servicios | ✗ | ✗ | ✗ | ✗ (spoke↔spoke) | vía su ISP |
| ADMIN | todo (con MFA) | ✓ | SSH/HTTPS | — | ✓ soporte | ✓ |
| GESTION | SNMP/agent | ✓ | — | ✗ | SNMP | NTP/updates |
| SERVIDORES | — | ✗ | syslog/SNMP traps | ✗ | ✗ | updates |

Todo bloqueo queda registrado (log en OPNsense → syslog → Zabbix). Suricata en modo IPS en WAN y DMZ.

