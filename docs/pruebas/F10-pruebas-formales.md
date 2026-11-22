# F10 — Pruebas formales (2026-11-22)

Medición de extremo a extremo con `scripts/f10-sonda.sh` (cada 0,5 s): **portal público** desde Internet (Cloudflare → túnel → DMZ → portal), **DNS del AD desde la Sede 1** (túneles + OSPF) y **salida a Internet desde ADMIN** (CARP + WAN).

| # | Prueba | Resultado | Aceptación | Req. |
|---|---|---|---|---|
| T1 | Matriz de zonas (`test-zones.sh`, 50 flujos: Internet, DMZ, sede, USUARIOS, ADMIN, GESTION, SERVIDORES) | ✅ **50/50** según la política (distingue filtrado de puerto cerrado por tiempo) | Solo pasa lo autorizado | RQ-09 |
| T2 | Caída de ISP1 hacia el Site A (60 s) | ✅ portal **6,7 s**, sede 5,7 s, ADMIN 3,1 s; retorno sin corte visible | Servicio continúa | RQ-08 |
| T3 | Camino de energía A (fw-a1 + sw-a1 + wsw-a1 suspendidos 60 s) | ✅ portal **1,1 s**, ADMIN 3,1 s, sede **23,5 s** (+8 s al volver fw-a1) | Servicios críticos arriba | RQ-07 |
| T4 | BD del portal destruida (`DROP DATABASE`) → restaurar desde nas-a | ✅ restauración **2 s**, caída total **5 s**; 3 trámites, misma huella | RTO ≤ 4 h | RQ-04 |
| T5 | Hacking: nmap desde Internet, hydra contra Authelia y SSH, movimiento lateral desde una sede | ✅ 4 000 puertos TCP filtrados (4 028 bloqueos registrados, IKE solo desde sedes); hydra **127 intentos, 0 aciertos** (bloqueo tras 3, la contraseña real también rechazada); sede → otras sedes/GESTION/ADMIN/RESPALDO: **0 equipos visibles** | Bloqueado y registrado | RQ-09 |
| T6 | Monitoreo: se detienen sw-a2 y LAM | ✅ alertas por correo a los **47 s / 56 s**, «RESUELTO» al volver; portal sin corte | Alerta + correo | RQ-10 |
| T7 | Ransomware: cifra 5 actas del archivo **y borra las instantáneas** con la clave restic robada | ✅ recuperación con el versionado WORM (*rewind*): documentos **idénticos (md5)** en **2 s**; repositorio sano | Datos dentro del RPO | P-R |
| T8 | **Pérdida total del Site A** (firewalls, switches WAN y cloudflared-a apagados) → P-A | ✅ **RTO del portal 86 s**; folio previo al desastre presente (RPO real 48 min < 1 h); trámite nuevo creado en B y devuelto a A en el retorno; sedes por `vti-b` con dc2 | RTO por servicio (Tabla 11) | P-A |
| T9 | Corte de energía prolongado | 📄 procedimiento de apagado ordenado documentado (`docs/PROCEDIMIENTOS-DR.md`); su parte técnica (P-A) es T8 | Apagado ordenado documentado | P-E |

## Hallazgos de las pruebas y correcciones (todas verificadas repitiendo la prueba)
| Prueba | Hallazgo | Corrección |
|---|---|---|
| T5 | SSH de los firewalls **con contraseña** y alcanzable desde las sedes; GUI/DNS del firewall también. Causa raíz: pf (FreeBSD 15.1/OPNsense 26.7) **no evalúa** lo que llega por una VTI con destino al propio firewall (ni con regla explícita) | SSH solo con clave y solo en GESTION/ADMIN; GUI solo en GESTION/ADMIN; los **kits** descartan todo hacia gestión, ADMIN, DMZ, RESPALDO e IP de los firewalls |
| T2 | Portal **146 s** caído al conmutar de WAN: cloudflared (HTTP/2) mantenía conexiones TCP «zombis» (keepalive de Go: 150 s) | cloudflared con **QUIC** (+ `tcp_retries2` corto): **6,7 s** |
| T3 | Sede 33,7 s al perder fw-a1 (las SA IPsec no se sincronizan entre FW en HA) | DPD 5 s y reintentos IKE cortos en los kits: 23,5 s |
| T6 | Un switch reiniciado quedaba **inalcanzable hasta 20 min** (MAC nueva del puerto de gestión) | se anuncia al gateway al arrancar: 5 s |
| T8 | Al conmutar DNS hay 1–2 min de respuestas mixtas (propagación en Cloudflare) | el retorno espera 120 s antes de apagar B |
| T8 | Zabbix comprobaba la GUI de los FW en la IP de SERVIDORES (cerrada desde T5) | se supervisan por su IP de ADMIN |
| T7 | (confirmado) la clave restic robada permite borrar instantáneas *lógicamente* | inocuo gracias a COMPLIANCE; procedimiento de *rewind* documentado |

## Limitaciones conocidas
- pf no filtra el tráfico de una VTI hacia el propio firewall: mitigado en el kit de la sede y endureciendo SSH/GUI; un kit comprometido podría intentar alcanzar los servicios del firewall (solo SSH con clave).
- Las SA IPsec no se replican entre fw-a1 y fw-a2: perder el maestro cuesta ~23 s a las sedes.
- En DR no hay escritorios (ts1), LAM ni Zabbix (servicios internos del Site A).
