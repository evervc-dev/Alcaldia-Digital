# Roles del personal, horarios y accesos de emergencia (23/11/2026)

| Rol (grupo AD) | Demo | Horario | Puede |
|---|---|---|---|
| `rol-admin` | admin.dc | sin límite | Todo; horarios; emergencias de hasta 72 h a Soporte, empleados o una persona |
| `rol-ti` | ti.guardia, tecnico.soporte | sin límite | Crear empleados (LAM), Zabbix Admin, tickets; emergencia de hasta 4 h **solo a Soporte** |
| `rol-soporte` | soporte.mesa | L–V 07–19 | Tickets, Zabbix en lectura, restablecer contraseñas de empleados |
| `funcionarios` | ana.funcionaria | L–V 07–19 | Portal, archivo y sus tickets |

Una cuenta **sin rol** no entra a la web ni a los escritorios. Instalar: `roles-setup.sh` → `glpi-setup.sh` → `services-setup.sh` → `zbx-setup.sh`.

## Cómo funciona
- La política vive en el AD (`OU=Politica-Acceso`, objetos `acc-*`), se replica a dc2 y solo la escriben `svc-politica` (gate) y Domain Admins.
- Las mismas reglas (`acc_politica.py`) valen para `gate` (web, en cada petición), `ts1` y los puestos Linux (al entrar; el agente lee cada 30 s).
- **Página:** `https://lam.evervc.dev/accesos` (solo WARP + MFA). Cada acceso de emergencia exige motivo, caduca solo, abre un **ticket P1** y envía correo. Al vencer, `ts1` y los puestos cierran la sesión que entró por él.
- **Sin AD:** 15 min con la última lectura; después se deniega. Rescate: `scripts/acceso-rescate.sh <usuario> <horas> "<motivo>"` (máx. 8 h; registro en `~/.local/state/acc/rescate.log`). Si Authelia tampoco autentica: SSH de firewalls, `Admin` de Zabbix y `glpi` de GLPI.
- **Zabbix:** usuarios del AD por rol; `monitor` pide Cloudflare Access + MFA + política + login de Zabbix.

## Pruebas (Authelia simulado; AD, GLPI, correo y ts1 reales)
| Prueba | Resultado |
|---|---|
| Ana y Soporte no ven `/accesos`; TI y admin sí; otro origen y cabecera falsa rechazados | ✅ |
| TI no puede: > 4 h, empleados, cambiar horario, encadenar | ✅ |
| Soporte fuera de horario denegado → TI da 4 h → entra en 0,4 s → revocado → denegado | ✅ |
| Excepción de 20 s caduca sola; replicada en dc2; ticket #84 con prioridad 5 y SLA | ✅ |
| `ts1`: proceso que imita la sesión de Soporte, cerrado tras revocar | ✅ |
| AD caído: con caché entra, sin caché deniega; dc1 caído usa dc2; rescate local | ✅ |
| Delegación: TI crea empleados, no TI; Soporte no crea; svc-politica no puede darse roles | ✅ |
| Zabbix: admin.dc = Super admin, ti.guardia = Admin, soporte.mesa = lectura, Ana no entra | ✅ |
| Navegador con TOTP, crear TI/Soporte en LAM, restablecer contraseñas con Soporte, escritorio RDP real | ⏳ sin probar |

## Pendiente
Login con AD en OPNsense · VLAN de Soporte · WARP para Soporte · qué rol entra en qué puesto · puestos Windows (no ejecutan el agente) · Zabbix solo consulta dc1.
