# F2 — Red del Site A, Tier II (2026-11-21)

Nodos: `fw-a1` / `fw-a2` (OPNsense 26.7, CARP), `sw-a1` / `sw-a2` (OVS, LACP "isl" ×2), `wsw-a1` / `wsw-a2` (segmentos WAN de cada ISP), `adm-pc` (VLAN 40, bond A/B).
Configuración de los firewalls: `config/opnsense/site-a.php` (rol a1|a2), aplicada con los modelos MVC de OPNsense (todos los campos validados).

| # | Prueba | Procedimiento | Resultado | Requisito |
|---|---|---|---|---|
| 1 | CARP: un solo MASTER | `ifconfig \| grep carp` | ✅ fw-a1 MASTER de las 8 VIP (WAN1, WAN2, VLAN 10–60), fw-a2 BACKUP | RQ-07 |
| 2 | **Falla de firewall** | ping 1.1.1.1 cada 200 ms desde adm-pc + `suspend` de fw-a1 | ✅ **≈ 3,1 s** de corte (16/199 perdidos); fw-a2 asume las VIP; preempt devuelve el rol a fw-a1 | RQ-07 |
| 3 | **Falla de proveedor (ISP1)** | ping cada 500 ms + `ip link set eth1 down` en isp1 | ✅ **≈ 4,5 s** de corte (9/100 perdidos); ruta por defecto → WAN2 y NAT por la VIP 198.51.100.4 | RQ-08 |
| 4 | **Falla del camino de energía A** | `suspend` simultáneo de fw-a1 + sw-a1 | ✅ **≈ 2–3 s** de corte; bond de adm-pc eth0→eth1, fw-a2 MASTER, HTTPS OK | RQ-07 / PDF §7 |
| 5 | Filtrado entre zonas (parcial) | sw-a1 (GESTION) → adm-pc (ADMIN) | ✅ bloqueado y registrado (`filterlog … vlan0.10,match,block`); GESTION → Internet permitido; ADMIN → GESTION permitido | RQ-09 |
| 6 | LACP entre switches | `ovs-appctl bond/show isl` | ✅ `lacp_status: negotiated`, 2 miembros activos | — |

## Hallazgos
- **Los uplinks de los FW van sin lagg.** En GNS3 la portadora no cae al apagar el otro extremo, así que un lagg failover nunca conmutaría. Diseño: fw-a1 → sw-a1 (camino A) y fw-a2 → sw-a2 (camino B); CARP pasa por el LACP entre switches.
- **Los bonds de los servidores usan monitoreo ARP** (`arp_interval 200`, `arp_ip_target` = VIP del gateway) por la misma razón; miimon no detecta la caída.
- **OPNsense 26.7 no monitorea los gateways si no se indica** (`monitor: ~`, sin dpinger). Hay que fijar `monitor_disable=0` y `monitor=<IP>`; además `monitor_killstates=1` para que los flujos ya abiertos no queden atados al ISP caído. Sin killstates, el ping en curso no se recuperó en 85 s.
- **Demotion 240 tras el arranque:** el bulk update de pfsync falla si el par aún no está listo. Corrección puntual: `sysctl net.inet.carp.demotion=-240`. No se repitió en los reinicios siguientes.
