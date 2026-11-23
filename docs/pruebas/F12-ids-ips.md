# IDS/IPS con Suricata en los firewalls (22/11/2026)

Cubre el alcance de la Fase 1 («registro de eventos y prevención de intrusiones (IPS) en los firewalls») y RQ-09 de la Fase 2.

## Diseño
| Pieza | Detalle |
|---|---|
| Motor | Suricata 8.0.6 (integrado en OPNsense 26.7), modo IDS (*PCAP live*), perfil de detección *low* (los FW del laboratorio tienen 1–1,5 GB) |
| Dónde | WAN1 (`vtnet0`) y WAN2 (`vtnet1`) de **fw-a1, fw-a2 y fw-b** |
| Reglas | ET Open para Suricata 8: `emerging-scan`, `emerging-dos`, `emerging-exploit`, `emerging-attack_response` |
| HOME_NET | Redes privadas, CGNAT de las sedes, públicas del laboratorio (203.0.113.0/24, 198.51.100.0/24) y tránsito 192.0.2.0/24 |
| Prevención | **Respuesta activa**: `acc-ids-vigia.py` (cron de OPNsense cada minuto, acción configd `acc ids-vigia`) añade la IP de origen de cada alerta a la tabla pf `ACC_IDS_BLOQUEO`. Una regla *block* con registro, la primera de cada WAN, la descarta; la entrada caduca a la hora. No bloquea redes de confianza (laboratorio, sedes, el otro sitio, 1.1.1.1/8.8.8.8) |
| Aviso | Trapper de Zabbix por FW: `ids.alertas`, `ids.ultima`, `ids.bloqueadas`. Disparador alto «IDS detectó un ataque desde Internet» (10 min tras la última alerta) → correo y **ticket en GLPI**. Aviso si el vigía no informa en 10 min |
| IaC | `config/opnsense/wan-ab.inc.php` (`acc_ids()`, `acc_acciones()`), alias en `site-a.php`/`site-b.php`, `opn-apply.sh <fw> filter ids`, `zbx-setup.py`, `lab-check.sh` |

## Pruebas
| # | Prueba | Resultado |
|---|---|---|
| I1 | `nmap -sS` desde `atacante-ext` (198.18.0.66) contra la WAN1 de fw-b (203.0.113.10) | ✅ 9 alertas «ET SCAN Suspicious inbound to PostgreSQL/Oracle SQL…»; IP en `ACC_IDS_BLOQUEO` en el minuto siguiente (registro `acc-ids` en syslog) |
| I2 | Nuevo intento del atacante | ✅ la regla de bloqueo descartó 10 paquetes (contadores de `pfctl -vsr`) |
| I3 | Zabbix y GLPI | ✅ problema «fw-b: IDS detectó un ataque…» con la firma en *opdata*; **ticket #5** en GLPI |
| I4 | `nmap -sS` contra la VIP del Site A (203.0.113.4) | ✅ 8 alertas en fw-a1 (maestro CARP), IP bloqueada a los **40 s**, **ticket #6** |
| I5 | Efecto en el servicio | ✅ portal 200 durante las pruebas; RAM libre después: fw-a1 667 MB, fw-a2 685 MB, fw-b 190 MB (Suricata ≈ 175 MB) |

## Problemas encontrados y arreglos
- `configctl ids restart` no arranca Suricata si antes no se regenera la plantilla: `configctl template reload OPNsense/IDS` (crea `/etc/rc.conf.d/suricata`). `opn-apply.sh ... ids` lo hace.
- El modelo del cron valida el comando contra la lista de acciones de configd y **la guarda en caché durante toda la ejecución de PHP**. Además, `acc_vigia_ipsec()` sobrescribía el archivo de acciones. Ahora `acc_acciones()` escribe un único `actions_acc.conf` con todas las acciones antes de crear el modelo del cron, y espera a que configd las liste.
- Limitación: es IDS + bloqueo a posteriori (las primeras sondas llegan antes del bloqueo). El IPS en línea (modo *divert*/*netmap*) queda como mejora; la DMZ no se inspecciona (solo recibe el túnel saliente de Cloudflare).
