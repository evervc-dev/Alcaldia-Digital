# Procedimientos de contingencia (Fase 5) — versión ejecutable en el laboratorio

## P-A · Pérdida total del Site A (probado en T8: RTO del portal 86 s)
1. **Confirmar** la pérdida (Zabbix/monitor sin respuesta del Site A, sedes por `vti-b`, alerta *Sede N: túnel hacia Site A caído*).
2. **Encender** en GNS3 los nodos en espera del Site B: `portal-b`, `authelia-b`, `gate-b`, `archivo-b`.
3. `bash scripts/dr-activar-b.sh` — detiene la réplica (portal-db-b pasa a primaria con la marca `DR-ACTIVO`), configura B, restaura el archivo desde **nas-b**, cambia el DNS de Cloudflare al túnel B y verifica.
4. Esperar 1–2 min de propagación en Cloudflare (algunas peticiones fallan mientras tanto).
5. Durante el DR: las sedes usan dc2 (DNS/Kerberos/LDAP) por el túnel al Site B; portal, archivo y login con MFA siguen operativos. **No disponibles** en B por diseño: escritorios ts1, LAM, Zabbix (monitor.evervc.dev) — dependen del Site A (Tabla 11: RTO de 24 h para servicios internos no críticos).
6. **Pérdida prolongada (> 24 h)**: tomar los roles FSMO en dc2 (`samba-tool fsmo seize --role=all`) y, antes de reincorporar dc1, eliminarlo del dominio y volver a unirlo (no reintroducir un DC con roles tomados). En la prueba de 6 min no fue necesario: dc2 escribe en el AD con su propio pool de RID.

## Retorno al Site A
1. Encender el borde del Site A (firewalls, switches WAN, cloudflared-a) y esperar a que `lab-check.sh` vea WAN y túneles.
2. `bash scripts/dr-retorno-a.sh` — copia los datos creados en B (trámites y documentos) al Site A, devuelve el DNS y espera 120 s de propagación.
3. **Reiniciar** `portal-db-b` (vuelve a ser réplica) y **apagar** `portal-b`, `authelia-b`, `gate-b`, `archivo-b`.

## P-E · Corte de energía prolongado (generador no arranca) — apagado ordenado del Site A
Con la autonomía de los SAI (Fase 3) en curso:
1. Declarar la contingencia y avisar (correo a TI desde Zabbix).
2. **Último respaldo**: `respaldo.sh ahora` en ts1, archivo, portal-db y dc1; comprobar en nas-b que llegó (`mc ls b/respaldos/repo`).
3. Ejecutar **P-A** (servicios a Site B) mientras el Site A sigue con energía.
4. Apagar en este orden: aplicaciones (portal, gate, authelia, archivo, lam, ts1) → bases de datos (portal-db, zbx-db) → Zabbix → **dc1** (solo después de `samba-tool drs showrepl` = ALL GOOD con dc2) → **nas-a** (tras comprobar la réplica) → switches de acceso → firewalls (fw-a2 y por último fw-a1) → switches WAN.
5. Al volver la energía: arrancar en orden inverso y seguir *Retorno al Site A*.

## P-R · Ransomware (probado en T7)
1. Aislar el equipo afectado (detener el nodo o su puerto de switch) y **no** pagar.
2. Aunque el atacante borre las instantáneas con la clave robada, el Object Lock **COMPLIANCE** conserva las versiones: en nas-a, `mc cp --recursive --rewind <tiempo> a/respaldos/repo/ /tmp/repo-antes/` y `restic -r /tmp/repo-antes restore ...`.
3. Rotar `RESTIC_S3_KEY` (cuenta de servicio) y las credenciales del equipo comprometido; reinstalar con `respaldo-setup.sh`.
