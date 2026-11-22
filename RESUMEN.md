# Alcaldía Digital — Resumen del laboratorio

> Simulación en GNS3 del centro de datos de la Alcaldía Digital: **Site A** (Tier II, principal), **Site B** (Tier I, recuperación en caliente), **3 sedes distritales** y publicación real en Internet con Cloudflare (`evervc.dev`).
> Estado al 22/11/2026: **MVP completo (F0–F10)**. Detalle técnico en `ESTADO.md`; evidencias en `docs/pruebas/`; procedimientos en `docs/PROCEDIMIENTOS-DR.md`; operación diaria en `APAGAR-ENCENDER.md`.

---

## 1. Qué hace el sistema, en una página

| Funcionalidad | Qué hace | Cómo lo hace |
|---|---|---|
| **Portal ciudadano** | Cualquier persona solicita y consulta trámites desde Internet | FastAPI + PostgreSQL, publicado por Cloudflare Tunnel; sin puertos abiertos en los firewalls |
| **Zona de funcionarios** | Atender trámites; archivo documental | Login único (Authelia) con usuario del AD + **TOTP**, y **horario laboral** por grupo |
| **Directorio (AD)** | Un usuario de la alcaldía sirve para todo: web, escritorios, NAS, puestos | Samba AD (`ad.alcaldia.lab`), dc1 en A y dc2 en B con réplica |
| **Escritorios por usuario** | Cada usuario tiene su escritorio XFCE y su `/home` | xrdp en ts1 (RDP), unido al dominio; horario con ventana explicativa |
| **Puestos unidos al dominio** | Un PC en una sede inicia sesión con la cuenta de la alcaldía | Debian + LightDM + winbind (`puesto-01`); guía para Windows en `docs/PUESTO-WINDOWS.md` |
| **Gestión de identidades** | TI crea, desactiva y mueve usuarios por web | LAM sobre LDAPS, **solo por VPN WARP**, con MFA; gestores de TI delegados por sede |
| **Alta disponibilidad (Tier II)** | Si cae un firewall, un switch, un proveedor o un camino de energía, el servicio sigue | CARP + pfsync, doble ISP, enlaces dobles (bond) a dos switches, LACP |
| **Sedes** | Cada sede llega al CD por 3 túneles cifrados con conmutación automática | Kit Docker (strongSwan + FRR + nftables + dnsmasq) tras CGNAT; OSPF elige el mejor túnel |
| **Recuperación ante desastre** | Si se pierde el Site A, el portal vuelve desde el Site B | Réplica horaria de la BD, servicios en espera, cambio de DNS en Cloudflare (`dr-activar-b.sh`) |
| **Monitoreo y alertas** | Ver el estado de la red y recibir correos cuando algo falla | Zabbix 7 (38 equipos, mapa de red) + correo a mailpit + **ticket automático en GLPI** |
| **Mesa de servicio** | El personal reporta incidencias; TI las atiende; las caídas abren tickets solas | GLPI 11 en `mesa.evervc.dev`, login único con el AD (perfil según grupo); Zabbix abre y resuelve tickets por la API |
| **Respaldos** | Copia diaria cifrada, inmutable, en otro sitio y fuera de línea | restic → NAS con Object Lock **COMPLIANCE** → réplica a nas-b → cinta simulada |
| **Acceso remoto de TI** | Administrar desde casa de forma segura | Cloudflare Zero Trust + **WARP**, solo para los correos autorizados |

---

## 2. Servicios expuestos y rutas

### Públicos (Internet → Cloudflare → túnel → nginx-dmz)
| URL | Qué es | Protección |
|---|---|---|
| `https://portal.evervc.dev/` | Portal ciudadano: inicio, `POST /solicitar`, `GET /consulta?folio=...` | Pública |
| `https://portal.evervc.dev/funcionarios` | Bandeja de trámites y `POST /funcionarios/atender` | Authelia (AD + TOTP), grupos `funcionarios` o `acceso-24h`, **horario** (gate) |
| `https://archivo.evervc.dev/` | Archivo documental (filebrowser), carpeta por usuario | Authelia + horario; usuario por cabecera `Remote-User` |
| `https://auth.evervc.dev/` | Login único (Authelia): contraseña del AD + TOTP; 3 fallos ⇒ bloqueo de 5 min | — |
| `https://monitor.evervc.dev/` | Zabbix (mapa, problemas, gráficas) | **Cloudflare Access** (PIN al correo del equipo TI) + login de Zabbix |
| `https://mesa.evervc.dev/` | Mesa de servicio GLPI: el personal abre tickets (vista Helpdesk); TI los atiende | Authelia (AD + TOTP) + horario; GLPI entra solo con la cabecera `Remote-User` (SSO). Perfil: `mesa-tecnicos` → Technician, `mesa-admins` → Admin, resto → Self-Service. `/apirest.php` cerrado (403) |

### Solo con WARP (VPN de Cloudflare, correos autorizados)
| Destino | Qué es |
|---|---|
| `https://lam.evervc.dev` | LAM: gestión de usuarios (grupo `gestores-identidad` o Domain Admins, + MFA) |
| RDP a `10.10.20.40` | Escritorio XFCE propio (ts1) |

### Internos (dentro del laboratorio)
| Servicio | Dirección |
|---|---|
| DNS/Kerberos/LDAP(S) | dc1 `10.10.20.10`, dc2 `10.20.20.10` |
| GUI y SSH de los firewalls | Solo desde GESTION/ADMIN: `https://10.10.40.2`, `.3` y `https://10.20.40.1`; SSH **solo con clave** (`scripts/fw.sh`) |
| Correo de pruebas (alertas) | mailpit `http://10.10.20.32:8025` |
| Consola de los NAS | nas-a `http://10.10.60.10:9001`, nas-b `10.20.60.10:9001` (grupo `nas-admins` del AD) |
| API de GLPI | `http://10.10.20.31/apirest.php`, solo desde la VLAN SERVIDORES (la usa Zabbix). Cuenta local de emergencia `glpi` (contraseña `GLPI_ADMIN_PASS` del `.env`) |

---

## 3. Qué hace cada nodo

### Borde e Internet simulado
| Nodo | Función |
|---|---|
| `internet-real` | NAT de GNS3: salida real a Internet (Cloudflare, actualizaciones) |
| `inet-core` | «Internet» del laboratorio: enruta (BGP) entre los ISP y la salida real |
| `isp1`, `isp2` | Proveedores 1 y 2: dan WAN a los sitios y **CGNAT** a las sedes (una IP pública por sede) |
| `atacante-ext` | Equipo hostil en Internet para las pruebas de hacking (nmap, hydra) |

### Site A (Tier II) — red `10.10.0.0/16`
| Nodo | IP | Función |
|---|---|---|
| `fw-a1`, `fw-a2` | VIP `.1`, `.2`/`.3` en cada VLAN | OPNsense en **CARP** (maestro/respaldo): firewall, NAT, IPsec/VTI, OSPF, DHCP |
| `wsw-a1`, `wsw-a2` | — | Switches WAN (camino de energía A / B) |
| `sw-a1`, `sw-a2` | gestión `10.10.10.11/.12` | Switches de acceso OVS con VLAN y LACP entre ellos; cada servidor va a los dos |
| `dc1` | `10.10.20.10` | Samba AD DC principal + DNS |
| `authelia` | `10.10.20.11` | Login único con TOTP y regulación de fuerza bruta |
| `gate` | `10.10.20.13` | Política de **horario laboral** por grupo para la web (pregunta a Authelia y al AD) |
| `portal` / `portal-db` | `10.10.20.20` / `.22` | Portal ciudadano y su PostgreSQL (con el esquema de Authelia) |
| `archivo` | `10.10.20.21` | Archivo documental (filebrowser) |
| `mailpit` | `10.10.20.32` | Buzón de pruebas: recibe alertas de Zabbix y correos de Authelia |
| `zbx-server`, `zbx-web`, `zbx-db` | `.30`, `.33`, `.34` | Monitoreo Zabbix |
| `glpi` / `glpi-db` | `10.10.20.31` / `.35` | Mesa de servicio GLPI 11 y su MariaDB 11.4 |
| `ts1` | `10.10.20.40` | Escritorios XFCE por RDP, `/home` por usuario |
| `lam` | `10.10.20.50` | Gestión de identidades (LDAP Account Manager) |
| `nginx-dmz` / `cloudflared-a` | `10.10.30.10` / `.11` | Proxy inverso de la DMZ / conector Cloudflare Tunnel y WARP (QUIC) |
| `nas-a` | `10.10.60.10` | NAS de respaldo (MinIO, WORM COMPLIANCE 7 días) |
| `adm-pc` | `10.10.40.50` | PC del personal de TI (VLAN ADMIN): punto de administración |
| `usr-pc`, `pc-gui` | VLAN 50 (DHCP) | Usuarios internos (`pc-gui` con escritorio gráfico, consola VNC) |

### Site B (Tier I, DR en caliente) — red `10.20.0.0/16`
| Nodo | Función |
|---|---|
| `fw-b` | OPNsense único (`10.20.x.1`) |
| `sw-b1`, `sw-b2` | Switches OVS |
| `dc2` | Segundo DC (réplica del AD, DNS secundario) |
| `portal-db-b` | Réplica de la BD del portal (copia cada hora; RPO 1 h) |
| `portal-b`, `authelia-b`, `gate-b`, `archivo-b` | **Apagados en espera**: se encienden solo en un DR |
| `nginx-dmz-b`, `cloudflared-b` | DMZ y túnel del Site B (siempre conectado, sin tráfico hasta el DR) |
| `nas-b` | Copia replicada de los respaldos |
| `tape` | Cinta LTO simulada: **apagada** (fuera de línea); al encenderla graba un cartucho. La tarea semanal la enciende, graba y la apaga sola |
| `adm-pc-b` | PC de administración del Site B |

### Sedes (`10.100.N.0/24`, N = 1..3)
| Nodo | Función |
|---|---|
| `kit-sede-0N` | Router de la sede (equivale al FortiGate 40F): 3 túneles (A-WAN1, A-WAN2, B), OSPF, DHCP, NAT a Internet local, filtro hacia la gestión del CD |
| `sw-sede-0N` | Switch de la sede |
| `pc-0N-a`, `pc-0N-b` | PC de funcionarios (DHCP del kit, DNS dc1/dc2) |
| `puesto-01` | Puesto Linux **unido al dominio** con login gráfico (Sede 1, consola VNC) |

---

## 4. Pruebas manuales y respuesta esperada del centro de datos

> Cómo provocar fallos en la GUI de GNS3:
> - **Apagar un equipo:** clic derecho → *Stop*, o *Suspend* para un corte instantáneo.
> - **Quitar un enlace:** clic derecho sobre el cable → *Suspend*; *Resume* lo restablece. **No lo borres.**
>
> Observa el efecto en `https://monitor.evervc.dev` y en mailpit, y confírmalo con `bash scripts/lab-check.sh` al terminar.

| # | Qué haces | Qué debe pasar | Tiempo medido |
|---|---|---|---|
| 1 | *Suspend* de `fw-a1` | `fw-a2` toma las 8 VIP (CARP); Internet y portal siguen. Las sedes renegocian sus túneles. Al volver, `fw-a1` recupera el rol | portal ≈ 1 s · ADMIN ≈ 3 s · sedes ≈ 23 s |
| 2 | *Suspend* del cable `isp1` ↔ `wsw-a1` (WAN1 del Site A) | La salida pasa a WAN2 (ISP2); los túneles de las sedes pasan a A-WAN2; cloudflared reconecta | portal ≈ 7 s · sedes ≈ 6 s · ADMIN ≈ 3 s |
| 3 | *Suspend* de `fw-a1` + `sw-a1` + `wsw-a1` (corte de la PDU A) | Todo sigue por el camino B (bond de los servidores a `sw-a2`, `fw-a2` maestro) | portal ≈ 1 s · sedes ≈ 23 s |
| 4 | *Stop* de `sw-a2` | Servicios sin corte (bond por `sw-a1`). Zabbix: «sw-a2 Unavailable» por correo; «RESUELTO» al volver | alerta < 1 min |
| 5 | *Stop* de `portal` | `portal.evervc.dev` da error; Zabbix alerta «servicio Portal caído». Al arrancarlo vuelve solo | alerta < 1 min |
| 6 | *Stop* de `dc1` | Los usuarios siguen entrando: Authelia, ts1 y las sedes usan **dc2**. Zabbix alerta | sin corte para el usuario |
| 7 | *Suspend* del cable `kit-sede-02` ↔ `isp2` (WAN de la sede) | Zabbix: túneles WAN1/WAN2 caídos y «Sede 2 AISLADA» (Disaster). Al volver, el kit reconecta solo | alerta ≈ 1 min · reconexión ≈ 10 s |
| 8 | *Stop* de `fw-a1` **y** `fw-a2` (el Site A sin firewalls) | Las sedes siguen funcionando por el **túnel al Site B** con dc2. El portal cae hasta activar el DR (prueba 14). Al volver, los túneles a A se restablecen solos | sedes ≈ 7 s |
| 9 | Login en `archivo.evervc.dev` con `ana.funcionaria` fuera de horario (fines de semana, o lunes a viernes fuera de 08:00–16:00) | Página explicando el motivo del rechazo | — |
| 10 | Login en `puesto-01` (consola VNC) con `ana.funcionaria` fuera de horario | Ventana con el motivo y cierre de sesión; con `tecnico.soporte` (`acceso-24h`) entra | — |
| 11 | 4 contraseñas falsas seguidas en `auth.evervc.dev` | Bloqueo de 5 min, incluso con la contraseña correcta | — |
| 12 | Desde `pc-01-a`: `nc -z -w3 10.100.2.1 53` o `nc -z -w3 10.10.40.2 443` | Bloqueado: ni otras sedes ni la gestión del CD son alcanzables | — |
| 13 | Crear un usuario en LAM (con WARP), dentro de `Sede-02` | Puede iniciar sesión en el portal (TOTP), en ts1 y en `puesto-01`; un gestor de sede no puede darle `acceso-24h` | — |
| 14 | **Pérdida del Site A**: *Stop* de `fw-a1`, `fw-a2`, `wsw-a1`, `wsw-a2`, `cloudflared-a` → encender `portal-b`, `authelia-b`, `gate-b`, `archivo-b` → `bash scripts/dr-activar-b.sh` | El portal vuelve **servido por el Site B** («Site B» en la portada), con los trámites anteriores. Retorno: `bash scripts/dr-retorno-a.sh` | 86 s |
| 15 | `bash scripts/tareas.sh ahora cinta` (o encender `tape` a mano) | Enciende `tape`, graba un cartucho con todos los respaldos (`/data/cartuchos/registro.log`) y lo **apaga** solo | ≈ 1 min en total |
| 16 | *Stop* de `lam` (o de cualquier servidor) y luego *Start* | Zabbix abre un **ticket en GLPI** (`mesa.evervc.dev`, categoría «Infraestructura», asignado a `zabbix`, urgencia según la severidad). Al volver, el ticket pasa a **Resuelto** con la solución automática. En Zabbix, el problema tiene el enlace «Ticket GLPI #N» | ticket ≈ 60 s · cierre < 1 min |
| 17 | Entrar a `mesa.evervc.dev` con `ana.funcionaria` y con `tecnico.soporte` | Ana ve la vista simple (crear/seguir sus tickets); el técnico ve la vista completa con todos los tickets. Ninguno escribe contraseña en GLPI (SSO) | — |

Pruebas automáticas equivalentes: `scripts/test-zones.sh` (50 flujos), `scripts/f10-sonda.sh` (mide cortes) y `scripts/lab-check.sh` (estado general).

---

## 5. Cómo funcionan los sistemas (por dentro)

- **Login y horario web:**
  1. nginx-dmz pregunta a `gate` (`auth_request`) en cada petición protegida.
  2. `gate` consulta a Authelia si hay sesión con MFA.
  3. Lee los grupos del AD y aplica `config/politicas/horario.conf`: `funcionarios` de lunes a viernes de 08:00 a 16:00; `acceso-24h` siempre.
  4. Fuera de horario devuelve una página con el motivo; en ts1 y en los puestos lo hace `horario.sh` con una ventana.
- **Portal:**
  - FastAPI genera un folio (`AAAAMMDD-XXXXXX`) y lo guarda en `portal-db`.
  - `/funcionarios` recibe el usuario por la cabecera `Remote-User` que pone nginx tras el login.
- **Túneles de sede:**
  - Cada kit **inicia** 3 túneles IKEv2 (atraviesan el CGNAT con NAT-T) hacia la VIP de A por WAN1 (coste 10), por WAN2 (coste 20) y hacia B (coste 100).
  - OSPF elige el de menor coste.
  - Si no hay túnel, una ruta *blackhole* impide que el tráfico interno salga a Internet.
  - Un vigilante relanza los túneles caídos cada 30 s.
- **Réplica y DR:**
  - `portal-db-b` copia la BD de A cada hora (si falla, reintenta a los 5 min).
  - En un DR se marca `DR-ACTIVO` para que no la pise, y Cloudflare pasa a apuntar al túnel B.
  - El AD replica en continuo (DRS).
- **Respaldos:**
  - Cada noche a las 02:00, restic cifra y deduplica: homes de ts1, archivo, volcado del portal, backup del AD, volcado de MariaDB de GLPI y `/var/glpi` (llave de cifrado y adjuntos).
  - Destino: nas-a, con versiones bloqueadas 7 días (ni root las borra), replicado a nas-b y copiable a cinta.
  - La cuenta de restic puede escribir, pero no destruir versiones.
- **Monitoreo:**
  - Zabbix hace ping a todo cada 20 s y comprueba puertos y servicios.
  - Lee por SNMP el estado de los túneles y OSPF de los kits.
  - Lee la antigüedad de la réplica (ODBC), la de los respaldos (restic, solo lectura) y la ocupación del NAS.
  - Envía correos de problema y de «RESUELTO».
  - Desde severidad *Media*, un webhook abre un ticket en GLPI (guarda su n.º como etiqueta del evento), añade seguimientos y lo resuelve al recuperarse.
- **Mesa de servicio (GLPI):**
  - nginx-dmz pasa el usuario autenticado (Authelia + horario) en `Remote-User`; Apache en `glpi` **descarta esa cabecera** si no viene de nginx-dmz (nadie de la VLAN puede suplantar).
  - GLPI crea al usuario la primera vez con sus datos del AD (LDAPS a dc1, réplica dc2) y le asigna el perfil por su grupo (reglas).
  - Notificaciones de GLPI por correo a mailpit. Todo se configura con `scripts/glpi-setup.sh` (idempotente).
- **Seguridad perimetral:**
  - No hay puertos abiertos en Internet: todo entra por Cloudflare.
  - Firewall por zonas con mínimo privilegio y registro de bloqueos.
  - SSH de los firewalls solo con clave y solo desde ADMIN/GESTION.
  - Los kits filtran el acceso de las sedes a la gestión.
- **Infraestructura como código:**
  - Todo se reconstruye con `scripts/` y `config/`.
  - Los secretos solo están en `.env` (fuera de git).
  - Las configuraciones de red se guardan saneadas en `configs/` (`backup-configs.sh`), **cada 24 h de forma automática** (`acc-tareas.timer` → `scripts/tareas.sh`, con commit local y aviso en Zabbix si falla o no se ejecuta).

---

## 6. Qué hay, qué hay a medias y qué se puede agregar

### ✅ Hecho y probado
- **Tier II en el Site A:**
  - CARP, doble ISP y caminos de energía A/B.
  - Bonds y LACP.
  - Medido: firewall ≈ 3 s, ISP ≈ 7 s, energía ≈ 1–3 s.
- **Site B en caliente:** DR completo en 86 s, con retorno sin pérdida de datos.
- **3 sedes replicables** (`new-sede.sh N`): hub-and-spoke, aisladas entre sí, failover WAN1 → WAN2 → B.
- **Identidad y acceso:**
  - AD con OU por sede y delegación.
  - MFA (TOTP).
  - Horario laboral con motivo visible.
  - Escritorios por usuario y puesto unido al dominio.
  - LAM solo por WARP.
- **Publicación segura:** Cloudflare Tunnel, Zero Trust/WARP y Access para el monitoreo.
- **Monitoreo:** Zabbix con alertas por correo, mapa de red y supervisión de túneles, réplica, NAS y respaldos.
- **Mesa de servicio:** GLPI en `mesa.evervc.dev` con SSO del AD, perfiles por grupo y tickets automáticos desde Zabbix (abrir y resolver, probado).
- **Respaldos 3-2-1:** WORM COMPLIANCE, réplica a nas-b, cinta y respaldo de configuraciones; resistentes al ransomware (probado).
- **Tareas programadas:** respaldo de configuraciones diario y cinta semanal automáticos (temporizador systemd en el host), vigilados por Zabbix.
- **Pruebas formales:** T1–T8 con evidencias; T9 documentada.

### 🟡 A medias / limitaciones conocidas
- **Puesto Windows** para la defensa:
  - La guía está lista; falta tu plantilla QEMU.
  - Falta el **horario en Windows** (script de inicio en NETLOGON o `logonHours`).
- **Servicios internos no disponibles en DR** (se quedan en el Site A): escritorios ts1, LAM, Zabbix y GLPI (sus respaldos sí están en nas-b).
- **Sedes al perder `fw-a1`:** ≈ 23 s de corte, porque OPNsense no sincroniza las SA IPsec entre los dos firewalls.
- **pf no filtra** el tráfico de las VTI dirigido al propio firewall. Está mitigado en los kits y con SSH/GUI restringidos.
- **Tareas programadas en el host:** corren con tu sesión abierta (temporizador systemd de usuario); con el equipo apagado se recuperan en la primera hora con el lab encendido.
- **Tarea manual:** la toma de roles FSMO en un DR largo está documentada, no ejecutada.
- **Correo:** las alertas van a mailpit (buzón de pruebas), no a un correo real.
- **Sistemas mínimos (portal, archivo):** son demostrativos y está previsto **actualizarlos después**. La arquitectura (Authelia, `gate`, cabecera `Remote-User`, réplica y respaldos) no cambia si se sustituye la aplicación.
- **Repositorio de prueba roto** `respaldos/restic` en los NAS: inocuo, se puede borrar (ver `ESTADO.md`).

### ➕ Se puede agregar
- **GLPI:** inventario automático de equipos (agente GLPI), catálogo de servicios y SLA por categoría; recolector de correo para abrir tickets por email.
- **Suricata** (IDS/IPS) en los OPNsense.
- **oxidized** (interfaz web con el historial de configuraciones) en lugar de `backup-configs.sh` + git.
- **Correo real** (SMTP saliente) para las alertas; alerta de cambios hechos en LAM.
- **Más disponibilidad en el DR:** Zabbix secundario o *proxy* en el Site B; escritorios de contingencia en B.
- **WebAuthn/llaves de seguridad** en Authelia, además de TOTP.
- **Más sedes:** `new-sede.sh 4` y siguientes, con los pasos de `ESTADO.md`.
