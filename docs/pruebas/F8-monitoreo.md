# F8 — Monitoreo y alertas (Zabbix 7.0 LTS) (2026-11-22)

Requisito del PDF: *monitoreo de equipos y servicios con generación de alertas* y *mapeo de la red para identificar fallas*. Fase 4: Zabbix con los umbrales de la Tabla 13.

## Despliegue
| Nodo | IP (VLAN 20, doble enlace sw-a1/sw-a2) | Imagen |
|---|---|---|
| zbx-db | 10.10.20.34 | acc/pg (PostgreSQL 16) |
| zbx-server | 10.10.20.30 | acc/zabbix-server (oficial 7.0 alpine + su-exec + psqlodbc) |
| zbx-web | 10.10.20.33:8080 | acc/zabbix-web (oficial nginx+php) |

Toda la configuración es código: `scripts/zbx-setup.sh` → `scripts/zbx-setup.py` (API JSON-RPC, idempotente). Secretos (`ZABBIX_ADMIN_PASS`, `ZBX_SNMP_COMMUNITY` como macro secreta) solo en `.env`.
Firewall: regla única `MONITOREO: zbx-server -> todos los equipos` (origen 10.10.20.30/32); el resto de SERVIDORES sigue cerrado.

## Qué se vigila (35 hosts)
| Ámbito | Cómo | Disparadores (Tabla 13) |
|---|---|---|
| Todos los equipos (FW, VIP CARP, switches, servidores, NAS, kits) | ICMP cada 20 s | equipo caído (≈ 1 min) |
| Servicios: DNS/Kerberos/LDAP/LDAPS/SMB (dc1, dc2), Authelia, gate, portal, archivo, PostgreSQL, ts1 RDP, LAM, mailpit, nginx-dmz, MinIO, GUI OPNsense | `net.tcp.service` (TCP/HTTP/LDAP/SMTP/HTTPS) | servicio caído (3 fallos seguidos) |
| Enlaces WAN Site A (gateways ISP1/ISP2) y túneles A↔B (172.16.0.2/.6) | ICMP | enlace/túnel caído |
| Túneles de cada sede hacia A (WAN1/WAN2) | ping desde el CD al extremo del kit en cada VTI | túnel caído (Average) |
| Túnel de cada sede hacia B, vecinos OSPF, CPU/red del kit | SNMP v2c (solo lectura, solo desde zbx-server) + `extend` | túnel B caído, < 3 vecinos OSPF, **sede AISLADA** (Disaster) |
| Réplica de la BD del portal (Site B) | ODBC: antigüedad de `replica_ok` | **> RPO 1 h** (High) |
| NAS A/B | métricas MinIO (Prometheus) | > 80 % (Warning), > 90 % (High) |
| Portal público https://portal.evervc.dev | escenario web desde Internet | inaccesible (ruta Cloudflare→túnel→DMZ) |

Alertas: correo a `ti@alcaldia.lab` (mailpit) para severidad ≥ Warning, con asunto `[Severidad] equipo: problema` y aviso de **RESUELTO** con la duración.
Mapa: *Monitoring → Maps → Alcaldía Digital* (Site A, Site B, sedes, Internet; los enlaces de túneles y réplica se ponen en rojo con su disparador).
Acceso: **https://monitor.evervc.dev** → Cloudflare Access (solo correos del equipo TI, PIN por correo) → login de Zabbix (Admin, contraseña en `.env`). Sin la cabecera de Access nginx-dmz responde 403.

## Pruebas
| # | Prueba | Resultado |
|---|---|---|
| M1 | Datos reales | ✅ túneles 1/1/1 y OSPF 3 por sede, NAS 17 %, réplica 907 s |
| M2 | Corte de la WAN de la Sede 3 (90 s) | ✅ alertas a los **61 s**: equipo caído (High), túneles WAN1/WAN2 (Average), **sede aislada** (Disaster) |
| M3 | Recuperación | ✅ túneles de nuevo **9 s** después de volver el enlace; correos **RESUELTO** (duró 59 s) |
| M4 | Correo de alerta | ✅ recibido en mailpit (`[Disaster] kit-sede-03: Sede 3: AISLADA (sin ningún túnel)`) |
| M5 | Publicación segura | ✅ `monitor.evervc.dev` sin sesión → 302 al login de Access; salto directo a nginx sin Access → 403 |
| M6 | `lab-check.sh` | ✅ todo OK (incluye sección Monitoreo y «sin problemas ≥ media») |

## Problemas resueltos
- Imágenes oficiales de Zabbix (usuario 1997, `/sbin/nologin`) → envoltorio root + `su-exec zabbix`; nginx reabre `/dev/stdout` y falla si el descriptor es de root → el log lo abre el propio usuario zabbix.
- `snmpd -c /etc/snmp/snmpd.conf` leía la configuración dos veces (extends duplicados) → `snmpd` sin `-c`.
- Plantillas «ICMP Ping» y «Linux by SNMP» comparten la clave `icmpping` → en los kits solo la de SNMP.
- La alerta de túnel basada en el propio kit no salta si la sede queda aislada → los túneles a A se comprueban desde el CD.
- Tras un corte de interfaz, strongSwan tardaba ~3 min en reintentar (backoff) → `retransmit_*` cortos (recupera en ~9 s); el bucle de reinicio de charon ahora recarga las conexiones (`swanctl --load-all`).

## SLA de disponibilidad mensual (Fase 4 Tabla 4 y §2.3) — 22/11/2026
- **Servicios de Zabbix S1–S6**, alimentados solo por los disparadores de disponibilidad con la etiqueta `servicio=Sx`: servicio caído, portal inaccesible desde Internet, NAS caído y trabajos de respaldo para S6. Los avisos de capacidad no descuentan.
- **S1 con redundancia:** «Directorio activo (dc1 o dc2)» solo cae si fallan los dos DC (regla *todos los hijos*); «Autenticación web (Authelia + horario)» cuenta aparte.
- **SLA mensuales:** S1 99,2 %, S3 96,8 % y S5 96,8 % en horario L–V 07:00–19:00; S2 99,4 %, S4 98,9 % y S6 96,7 % en 24×7. Zona horaria America/El_Salvador.
- **Informe mensual:** `scripts/sla-informe.sh [meses]`. Muestra la caída del mes frente a la permitida (2 h, 4,38 h, 8 h, 8,03 h, 8 h, 24,09 h), la disponibilidad proyectada y si se cumple. En la GUI: *Servicios → Informe de SLA*.

| # | Prueba | Resultado |
|---|---|---|
| M7 | *Stop* de `portal` y de `dc1` durante unos 3 min | ✅ S2 en problema; **S1 sigue OK** (dc2 responde). Informe: S2 con 3 min de caída, 99,99 % en el mes, ✔ cumple (margen 4 h 19 min) |

- Gotcha: en la API de Zabbix 7, `algorithm` 1 = «el más grave **si todos** los hijos tienen problema» y 2 = «el más grave de los hijos» (al revés de lo intuitivo).

## Sala de cómputo simulada: UPS, generador y ambiente (Fase 3 §4, Fase 4 Tabla 13) — 22/11/2026
GNS3 no emula energía ni clima. `scripts/sensores.py` actúa como las tarjetas de red de los UPS (NMC 3) y los sensores ASHRAE. Lo lanza el servicio `acc-sensores` (systemd --user, instalado con `tareas-instalar.sh`) y envía cada minuto por trapper a los hosts `sala-a` y `sala-b`.

| Valor de diseño (Fase 3) | Simulado |
|---|---|
| Carga de TI 3,29 kW (A) / 2,29 kW (B) | ±3 % |
| UPS de 4,8 kW: A y B al 34,3 % cada uno (68,6 % si falla el otro); B1 al 47,7 % | calculado |
| Autonomía: recta por la curva del fabricante (3 000 W → 6,12 min; 3 500 W → 4,88 min) | 9,4 min (A, dos UPS) · 7,9 min (B) · 5,4 min (A con un UPS) |
| Sala 22–24 °C y 45–55 % HR en normal | aleatorio en rango |

Disparadores de la Tabla 13: temperatura fuera de 18–27 °C (P2), HR fuera de 20–80 % (P3), carga del UPS > 80 % (P2), **UPS en baterías (P1)**, carga de TI > 4,39 kW (P4: Información, sin ticket), falla de arranque del generador (P2), sitio en generador (P3), UPS fuera de servicio (P2) y autonomía < 2 min en baterías → **aplicar P-E** (desastre).

| # | Escenario | Resultado |
|---|---|---|
| E1 | `sensores.py a corte` | ✅ 21:19:27 UPS A y B en baterías (P1, tickets #31/#32) → 21:20:00 generador en marcha: resueltos y tickets cerrados; «alimentado por el generador» (P3, #33) hasta `a normal` |
| E2 | `sensores.py b generador-falla` | ✅ falla de arranque (P2, #34) + UPS B1 en baterías (P1, #35); la autonomía bajó de 8,0 a 1,1 min y a las 21:28 «aplicar P-E» (desastre, #36) |
