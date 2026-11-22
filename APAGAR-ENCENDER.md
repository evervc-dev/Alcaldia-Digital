# Apagar y encender el laboratorio (resumen rápido)

> Detalle y casos raros: `docs/OPERACION.md`. Todo lo necesario está en **imágenes `acc/*`** o en **volúmenes**:
> al cerrar, GNS3 borra los contenedores y al reabrir los recrea sin perder configuración, datos, usuarios ni la unión al dominio.

---

## 🔴 APAGAR

1. **(Opcional) Comprobar que todo está bien antes de cerrar**: así, si al volver algo falla, sabrás que lo causó el arranque.
   ```bash
   cd ~/Documents/acc-project/Alcaldia-Digital && bash scripts/lab-check.sh
   ```
2. **Guardar el trabajo en git**: haz *push* desde VS Code si hay commits pendientes.
3. En la GUI de GNS3: **■ Stop all**. Espera a que **todos** los nodos queden en rojo; los 3 OPNsense tardan 1–2 min en apagarse por ACPI.
   - ⚠️ No fuerces el cierre mientras los OPNsense siguen en verde: podría corromperse su disco.
4. **File → Close project** y después cierra la GUI de GNS3.
5. Apaga el PC con normalidad.

> El WARP de tu Windows o celular puede quedar conectado: solo dejará de llegar al laboratorio mientras esté apagado.

---

## 🟢 ENCENDER

1. Enciende el PC. No hace falta preparar nada del host: módulos, red NAT de libvirt, ufw, busybox y `gns3_server.conf` ya son persistentes.
2. Abre la GUI de GNS3 → **File → Open project → ACC-Lab**.
3. **▶ Start all**.
   - Después **detén** los 4 nodos *en espera* del Site B: `portal-b`, `authelia-b`, `gate-b` y `archivo-b`. Solo se encienden en una recuperación ante desastre (DR).
4. Espera unos **4 min**. En ese tiempo arrancan los OPNsense, suben los túneles A↔B y de las sedes, Samba, Authelia y Zabbix.
5. Comprueba el laboratorio:
   ```bash
   cd ~/Documents/acc-project/Alcaldia-Digital && bash scripts/lab-check.sh
   ```
   Debe terminar en **`RESULTADO: todo OK`**. Si algo falla, espera 1–2 min y repítelo: muchos servicios se reintentan solos.
6. Si persiste algún fallo, mira la tabla de abajo o pide al agente: *«lee ESTADO.md y APAGAR-ENCENDER.md y revisa lab-check»*.

### Qué debería funcionar después

| Servicio | Cómo comprobarlo |
|---|---|
| Portal público | https://portal.evervc.dev |
| Archivo y funcionarios, con MFA y horario | https://archivo.evervc.dev |
| Monitoreo | https://monitor.evervc.dev (PIN de Access → `Admin` + `ZABBIX_ADMIN_PASS`) |
| LAM y escritorios RDP | Solo con **WARP** conectado: https://lam.evervc.dev y RDP a `10.10.20.40` |
| Puesto unido al dominio | En GNS3, clic derecho en `puesto-01` → Console (VNC) |

> Durante los primeros minutos Zabbix puede enviar a mailpit alertas de «caído» seguidas de «RESUELTO». Es normal mientras todo termina de arrancar.

---

## 🛠️ Si algo sale en rojo en `lab-check.sh`

| Fallo | Solución |
|---|---|
| `fw-a1` no es MASTER de las 8 VIP CARP | `bash scripts/fw.sh fw-a1 'sysctl net.inet.carp.demotion=-240'` |
| Portal público da 502/530 | Reiniciar el nodo `cloudflared-a` |
| OSPF A↔B con menos de 2 túneles | Esperar 1 min; si sigue, `bash scripts/opn-apply.sh fw-b strongswan` (necesita el servidor de la nota ¹) |
| Una sede con menos de 3 túneles | Esperar 1 min; si sigue: `docker exec GNS3.kit-sede-0N.<id> swanctl --load-all` |
| Authelia no arrancada | Se reintenta sola; si no, reiniciar el nodo `authelia` |
| Zabbix no responde | Comprobar que `zbx-db`, `zbx-server` y `zbx-web` están encendidos. Si sigue, `bash scripts/services-setup.sh` y reiniciar los 3 nodos |
| Zabbix reporta problemas tras más de 5 min | Abrir monitor.evervc.dev → *Problems*: indica el equipo o servicio exacto |
| Un switch con puertos sin enlace | Ver `AGENTS.md` regla 13: detener el nodo, rehacer los enlaces y arrancarlo |

¹ `opn-apply.sh` descarga los scripts desde un servidor HTTP del host. Si hace falta, ábrelo en otra terminal:
```bash
cd ~/Documents/acc-project/Alcaldia-Digital/config/opnsense && python3 -m http.server 8088 --bind 192.168.122.1
```

`<id>` es el identificador del proyecto: `88f8f32e-4b4f-4e25-9a8b-ac0c9c71c5f9`.

---

## 💡 Consejos
- **Pausa corta sin apagar el PC:** en *File → Edit project*, la opción «Leave this project running in the background when closing GNS3» permite cerrar solo la GUI con el laboratorio en marcha.
- **No** cambies adaptadores ni borres nodos mientras están en marcha (AGENTS.md reglas 13 y 15).
- La RAM libre normal con todo encendido es de unos 8 GB.
