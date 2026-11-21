# F5 — Servicios críticos, escritorios, horario, NAS y publicación (2026-11-21)

## Componentes
| Nodo | IP | Función |
|---|---|---|
| nas-a / nas-b | 10.10.60.10 / 10.20.60.10 | MinIO: bucket `respaldos` con Object Lock (GOVERNANCE 7 d), réplica A→B, login con AD (`nas-admins`) |
| ts1 | 10.10.20.40 | Escritorios XFCE por RDP (xrdp 0.10), unido al AD, `/home/ALCALDIA/<usuario>` automático |
| authelia | 10.10.20.11 | MFA TOTP sobre AD (LDAPS validado con CA propia); almacenamiento en PostgreSQL (esquema `authelia`, replicado a B) |
| gate | 10.10.20.13 | horario-gate: encadena Authelia + política de horario (`config/politicas/horario.conf`) |
| portal / portal-db | 10.10.20.20 / .22 | Portal de trámites (FastAPI) + PostgreSQL |
| archivo | 10.10.20.21 | filebrowser con autenticación proxy (Remote-User) y carpeta personal por usuario |
| nginx-dmz / cloudflared-a | 10.10.30.10 / .11 | Proxy inverso DMZ + Cloudflare Tunnel `acc-site-a` |
| mailpit | 10.10.20.32 | SMTP del laboratorio (códigos de registro TOTP, alertas) |
| pc-gui | VLAN 50 (DHCP) | Cliente gráfico (consola VNC): RDP a ts1 + navegador |
| Site B (DR) | 10.20.x | portal-db-b (réplica horaria), nginx-dmz-b, cloudflared-b (túnel `acc-site-b`) en marcha; portal-b, authelia-b, gate-b, archivo-b **en espera** |

Publicación: `portal|archivo|auth.evervc.dev` → Cloudflare → túnel A → nginx-dmz. DR: `scripts/dr-dns-switch.sh B|A`.

## Pruebas
| # | Prueba | Resultado | Requisito |
|---|---|---|---|
| 1 | Portal público desde Internet | ✅ `https://portal.evervc.dev` 200, «Servido desde: Site A» | RQ-02 |
| 2 | Áreas protegidas | ✅ `/funcionarios` y `archivo` → 302 al login de Authelia | RQ-01 |
| 3 | Primer factor contra AD | ✅ tecnico.soporte 200 OK; credenciales erróneas → 401 | RQ-01 |
| 4 | **Horario en escritorio (RDP)** | ✅ ana.funcionaria (sábado): **ventana con el motivo** y cierre de sesión; registro en `/var/log/acc-horario.log` (img/F5-rdp-fuera-de-horario.png) | requisito del usuario |
| 5 | Escritorio de usuario 24 h | ✅ tecnico.soporte: escritorio XFCE; homes creados automáticamente (img/F5-rdp-escritorio-24h.png) | requisito del usuario |
| 6 | Horario en web (gate) | ✅ ana.funcionaria → 403 (página con el motivo); tecnico.soporte → 200 | requisito del usuario |
| 7 | NAS inmutable | ✅ borrado de una versión bloqueada → «WORM protected»; copia en nas-b | Fase-5 §3 |
| 8 | NAS con cuentas AD | ✅ admin.dc obtiene credenciales STS; usuarios fuera de `nas-admins` sin permisos | — |
| 9 | Réplica del portal a B | ✅ `réplica OK desde 10.10.20.22`, marca de tiempo en `replica_ok` (RPO 1 h) | RQ-04 (S2) |
| 10 | Servicios DR listos | ✅ portal-b «Site B», authelia-b arranca sobre la BD replicada, cloudflared-b conectado (4 conexiones) | Fase-5 P-A |
| 11 | MFA completo (TOTP) | ⏳ **lo valida el usuario en el navegador** (código de registro en mailpit) | RQ-01 |

## Decisiones y problemas relevantes
- **Horario por política de grupo y no por `logonHours`:** con logonHours el DC rechaza antes de la sesión y ni xrdp ni Authelia muestran el motivo (probado). Decisión del usuario: grupo `funcionarios` restringido y `acceso-24h` exento; el mensaje se muestra en el escritorio y en la web.
- Imágenes envoltorio (`acc/pg`, `acc/authelia`, `acc/nginx`, `acc/cloudflared`): las oficiales no declaran volúmenes o no traen shell, y GNS3 necesita ambas cosas.
- CA propia para LDAPS: el certificado autofirmado de Samba tiene serial negativo y Go (Authelia) lo rechaza.
- GNS3 3.1 alfa: cambiar adaptadores o borrar nodos en marcha deja enlaces fantasma (ver AGENTS.md 13 y 15).
