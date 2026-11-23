# Mesa de servicio GLPI (`mesa.evervc.dev`) — diseño y pruebas (22/11/2026)

## Diseño
| Pieza | Detalle |
|---|---|
| Nodos | `glpi` 10.10.20.31 (GLPI 11.0.11 oficial, `acc/glpi:1.0`) y `glpi-db` 10.10.20.35 (MariaDB 11.4 LTS, `acc/glpi-db:1.0`); bond a `sw-a1` y `sw-a2`, VLAN 20 |
| Publicación | Cloudflare Tunnel → `nginx-dmz` → Authelia (AD + TOTP) + `gate` (horario) → `glpi:80`. `/apirest.php`, `/api.php` y `/api/` devuelven 403 desde Internet |
| Inicio de sesión | SSO: nginx envía `Remote-User`; GLPI usa `HTTP_REMOTE_USER` y crea al usuario con sus datos del AD (directorio LDAPS dc1 + réplica dc2, cuenta `svc-lectura`) |
| Anti-suplantación | `acc-sso.conf` en Apache: si la petición no viene de 10.10.30.10 (nginx-dmz) se **borra** `Remote-User` |
| Perfiles | Reglas de autorización por `memberof`: `mesa-tecnicos` → Technician, `mesa-admins` → Admin (perfil por defecto); el resto → Self-Service (vista Helpdesk) |
| Zabbix → GLPI | Webhook propio (`zbx-setup.py`): problema de severidad ≥ Media → ticket de incidente (categoría «Infraestructura (alerta de Zabbix)», urgencia = severidad, asignado a `zabbix`); n.º guardado en la etiqueta `__zbx_glpi_ticket`; actualización → seguimiento; recuperación → solución (estado Resuelto). Enlace «Ticket GLPI #N» en el menú del evento |
| API | Cliente API solo para 10.10.20.0/24; usuario `zabbix` (Technician) con contraseña en macro secreta `{$GLPI_ZABBIX_PASS}` |
| Correo | Notificaciones de GLPI → mailpit (10.10.20.32:1025) |
| Respaldos | `glpi-db`: `mariadb-dump --all-databases --single-transaction` (TIPO=mysqldump); `glpi`: `/var/glpi` (config, **llave glpicrypt.key**, adjuntos), cada noche a nas-a (WORM) → nas-b → cinta |
| IaC | `images/glpi*`, `services-setup.sh` (secretos), `glpi-setup.sh` (configuración por SQL + API, idempotente), `zbx-setup.py`, `cf-setup.sh` (DNS `mesa`), `ad-setup.sh` (grupos) |

## Pruebas
| # | Prueba | Resultado |
|---|---|---|
| G1 | Bind LDAPS desde `glpi` con la CA del laboratorio | ✅ `LDAPS bind OK` |
| G2 | SSO de `tecnico.soporte` (cabecera desde nginx-dmz) | ✅ usuario creado desde el AD, perfil por defecto **Technician**, entra a `front/central.php` |
| G3 | SSO de `ana.funcionaria` | ✅ perfil Self-Service, entra a la vista **Helpdesk** |
| G4 | Misma cabecera `Remote-User: admin.dc` enviada desde `portal` (otro servidor de la VLAN) | ✅ ignorada: formulario de login, el usuario **no** se crea |
| G5 | `https://mesa.evervc.dev/` desde Internet sin sesión | ✅ 302 a `auth.evervc.dev` (MFA) |
| G6 | `https://mesa.evervc.dev/apirest.php/initSession` desde Internet | ✅ 403 |
| G7 | *Stop* de `lam` | ✅ ticket abierto en **60 s** (medido en los tickets #1 y #2), asignado a `zabbix` desde el #2, urgencia 4 |
| G8 | Recuperación del problema | 🟡 El #3 pasó solo a **Resuelto**, pero con `lam` **todavía apagado** (39 s; causa no confirmada, quizá la reconfiguración de Zabbix). El cierre al recuperarse de verdad quedó probado después con la sala simulada (tickets #31–#36, F8) |
| G9 | Respaldo de `glpi-db` y `glpi` | ✅ OK en 2 s y 1 s; Zabbix y `lab-check` vigilan su antigüedad |

## Problemas encontrados y arreglos
- Cambiar una propiedad (`environment`) de un nodo Docker cuya imagen se había reconstruido hizo que GNS3 **borrara el contenedor** y dejara el nodo inservible («No such container»): se recreó el nodo (GLPI aún estaba vacío). Regla: para cambiar la imagen, recrear el nodo (ya documentado) o esperar a reabrir el proyecto.
- La macro `{EVENT.TAGS.__zbx_glpi_ticket}` llega como `*UNKNOWN*` cuando aún no hay ticket: el webhook solo acepta números.
- GLPI añade Self-Service (perfil por defecto) a los usuarios creados por API: la sesión de `zabbix` no podía resolver tickets. `glpi-setup.sh` deja solo Technician como perfil por defecto.
- GLPI rechaza volver a poner la misma contraseña (historial): `glpi-setup.sh` solo la fija al crear el usuario.
- Tickets #1 y #2 son de estas pruebas (el #1 se cerró a mano, el #2 con la cuenta `zabbix` por la API).

## Reporte ciudadano de fallas → ticket P4 (Fase 4 §2.2)
- `https://portal.evervc.dev/reportar` (público): nombre, contacto opcional, sede, tipo de falla y detalle. Se guarda en `portal-db` (tabla `reportes`, folio `R-AAAAMMDD-XXXXXX`) y se abre un ticket con la cuenta `portal` (Self-Service): urgencia e impacto bajos → **prioridad Baja = P4**, categoría «Portal ciudadano: reporte de falla».
- Sin GLPI (caída o DR en B): «Pendiente de registro»; un hilo del portal reintenta cada 5 min. Antiabuso: campo trampa, longitudes máximas y 20 reportes/min.

| # | Prueba | Resultado |
|---|---|---|
| G10 | Reporte desde Internet (con `<script>` en el detalle) | ✅ folio `R-20261123-C3EAB9` → **ticket #7**, prioridad 2 (Baja), HTML escapado |
| G11 | Categoría y hora local | ✅ ticket #8 en «Portal ciudadano: reporte de falla»; consulta con hora de El Salvador |
| G12 | Reporte con `glpi` apagado y encendido después | ✅ «Pendiente de registro» → **ticket #9** a los 274 s de volver GLPI |

## Catálogo, horario y SLA (Fase 4 Tablas 1, 2 y 6)
- **Categorías**: S1 Identidad, S2 Portal, S3 Archivo, S4 Monitoreo, S5 Mesa, S6 Respaldos y «Kit de sede y conectividad». Dentro de ellas, las solicitudes estándar de la Tabla 2: alta/baja/rol de cuenta (P4), restablecer contraseña o 2FA (P3), restaurar documento (P3), alta de trámite (P4, cambio normal) y revisión del kit (P3). «Portal ciudadano» va dentro de S2 y «Infraestructura (alerta de Zabbix)» dentro de S4.
- **Calendario** «Mesa de servicio L-V 07:00-19:00». **SLM** «P1 (guardia 24x7)», sin calendario: el tiempo corre siempre. **SLM** «P2-P4», con el calendario de la mesa.
- **SLA**: P1 15 min / 4 h · P2 30 min / 8 h · P3 2 h / 24 h · P4 8 h / 72 h (respuesta / resolución).
- **Reglas de negocio** (RuleTicket, al crear y al modificar): categoría de solicitud estándar → prioridad; prioridad → SLA. El criterio *prioridad* es una lista: solo admite «es», no expresiones regulares, así que hay una regla por valor (6 y 5 = P1, 4 = P2, 3 = P3, 2 y 1 = P4).
- **Zabbix → prioridad**: severidad Desastre y Alta → P1, Media → P2, Advertencia → P3, Información → P4 (vía urgencia/impacto y la matriz de GLPI). Severidades alineadas con la Tabla 13: servicio caído y Sede aislada = P1; túnel caído, réplica atrasada e IDS = P2; NAS > 80 % y respaldo no hecho = P3.
- **Hora local**: PHP con `America/El_Salvador`; zonas horarias de GLPI habilitadas (la BD guarda UTC).

| # | Prueba | Resultado |
|---|---|---|
| G13 | Solicitud «Restablecimiento de contraseña…» creada el domingo a las 20:31 | ✅ prioridad 3 → SLA P3; vence la respuesta el lunes 09:00 y la resolución el miércoles 07:00 (24 h hábiles) |
| G14 | Incidente urgencia 5 / impacto 5 | ✅ prioridad 5 → SLA P1 24×7; respuesta a los 15 min, resolución a las 4 h |
| G15 | Reporte ciudadano desde el portal | ✅ prioridad 2 → SLA P4 (8 h / 72 h hábiles) |
| G16 | *Stop* de `lam` | ✅ ticket de Zabbix con prioridad 5 → SLA P1 |
- Problema encontrado: el calendario se calculaba en UTC (PHP del contenedor) → `zz-acc-tz.ini` en la imagen `acc/glpi`.
