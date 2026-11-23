# F9 — Respaldos (2026-11-22)

Fase 4: regla 3-2-1 con copia inmutable; RPO 24 h para datos de usuario (1 h para la BD del portal, cubierto por la réplica de F5).

## Arquitectura
| Capa | Qué | Dónde |
|---|---|---|
| 1. Copia diaria | **restic** (cifrado AES-256, deduplicado) a las **02:00** hora local | Cada servidor sube a `nas-a` → bucket `respaldos/repo` |
| 2. Inmutable | **Object Lock COMPLIANCE 7 días** + versionado: nadie (ni root) borra o acorta la retención | nas-a y nas-b |
| 3. Fuera del sitio | Replicación `nas-a → nas-b` (Site B) **sin propagar borrados de versiones** | nas-b |
| 4. Fuera de línea | Cinta LTO simulada `tape` (Site B): al encenderla graba un cartucho fechado desde nas-b; luego se **apaga** (air gap) | tape 10.20.60.20 (automática cada 7 días: `scripts/tareas.sh`) |
| Configuraciones | `scripts/backup-configs.sh`: copia completa (WORM) en el NAS + copia **saneada** versionada en `configs/`, automática cada 24 h (`acc-tareas.timer`) | nas-a + git |
| Mantenimiento | nas-a 04:00: `restic forget` (7 diarias, 4 semanales, 12 mensuales) `--prune` + `restic check` | nas-a |

| Equipo | Qué se respalda |
|---|---|
| ts1 | `/home` (escritorios y documentos de todos los usuarios) |
| archivo | `/srv` y `/database` (archivo documental) |
| portal-db | `pg_dumpall` (BD + roles) |
| dc1 | `samba-tool domain backup offline` (AD completo, recuperable con `domain backup restore`) |

Cuentas MinIO (cuentas de servicio; con LDAP activo no hay usuarios internos): `restic` (escribe y borra objetos, **no** puede borrar versiones ni tocar la retención) y `restic-lectura` (Zabbix y cinta). Firewall: SERVIDORES → NAS de su sitio solo TCP 9000.
Zabbix: antigüedad del último respaldo por equipo, leída del propio repositorio; alerta a las 26 h.
Instalación: `nas-setup.sh` (bucket, cuentas, repo) → `respaldo-setup.sh [ahora]` (script + env en el volumen de cada equipo; las imágenes traen restic estático 0.17.3 y arrancan el bucle).

## Pruebas
| # | Prueba | Resultado |
|---|---|---|
| B1 | Primer respaldo de los 4 equipos | ✅ 1–3 s cada uno; 4 instantáneas |
| B2 | Replicación a Site B | ✅ mismos objetos en nas-a y nas-b |
| B3 | **Ataque con la clave de restic** (borrar versiones, quitar retención) | ✅ *Access Denied* / *Object is WORM protected* |
| B4 | **Ataque con la cuenta ADMIN** (quitar retención, borrar con `--bypass`) | ✅ denegado (COMPLIANCE) |
| R1 | Usuario borra un documento de su escritorio → restaurar | ✅ 1 s, mismo hash y mismo dueño (ana.funcionaria) |
| R2 | BD del portal: 3 trámites creados por Internet → respaldo → restauración en BD de prueba | ✅ 3 trámites, misma huella md5, 1 s |
| R3 | **DR: restaurar desde nas-b** sin tocar el Site A (archivo + backup del AD) | ✅ 2 s; backup del AD de 1,6 MB |
| R4 | Cinta: cartucho grabado y repositorio abierto **solo desde el cartucho** | ✅ 53 objetos/131,7 MB; `restic check`: *no errors were found* |
| B5 | Zabbix lee la antigüedad de los 4 respaldos | ✅ 60–110 s |
| B6 | Configuraciones de 3 FW, 6 routers/kits FRR y 9 switches | ✅ completa (WORM) + saneada en git sin secretos (guardia contra el .env) |

## Incidentes y lecciones
- **La primera versión con Object Lock GOVERNANCE NO protegía:** la clave de restic pudo quitar la retención y, con ella quitada, la cuenta admin borró una versión; la replicación con `delete` propagó el borrado a nas-b. Se perdió el repositorio de prueba (copias de 10 min). Corregido con **COMPLIANCE** y replicación sin `delete`; repetido el ataque: denegado. El repositorio roto (`respaldos/restic`) quedó sin borrar.
- Tras el reinicio del PC, MinIO arrancó antes que el DC y **desactivó LDAP**: vigilante en la imagen del NAS que lo reinicia cuando el DC responde.
- Con LDAP activo MinIO no admite usuarios internos → cuentas de servicio.
- El restic de Alpine no es estático (no funciona en Debian) → binario oficial `restic/restic:0.17.3`.
- `MINIO_ROOT_PASS` se mostró en una traza de depuración → **rotada**.

## Corrección (23/11/2026): los respaldos «diarios» no se ejecutaban solos
`HORA_UTC='08'` es un octal inválido en `$(( ))`: el bucle de ts1, portal-db, dc1 y zbx-db moría al arrancar, y `archivo` (imagen original) no tenía bucle tras un reinicio. **Todas las copias anteriores de esos equipos se lanzaron a mano.**
Arreglo: se quita el cero, se respalda a los 5 min de arrancar y `tareas.sh` reinstala los bucles que falten. Verificado: 7 instantáneas automáticas a las 14:13 UTC. La ejecución de las 02:00 todavía no se ha observado.
