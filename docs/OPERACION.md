# Operación del laboratorio: apagar y encender

## Apagar (fin de jornada)
1. En la GUI de GNS3: **File → Close project** (o el botón ■ *Stop all* y luego cerrar). GNS3 detiene los nodos; los OPNsense hacen un apagado ACPI (≈1–2 min). **Esperar** a que termine.
2. Cerrar la GUI y apagar el equipo con normalidad.
> Al cerrar, GNS3 **borra los contenedores** y al reabrir los recrea desde las imágenes `acc/*`. Solo persisten los volúmenes (configuración, datos, unión al dominio, conf.db de los switches). Todo lo necesario está en volúmenes o en las imágenes.

## Encender (al día siguiente)
1. Encender el equipo. El host ya deja todo persistente: módulos (`/etc/modules-load.d/acc-gns3.conf`), red NAT de libvirt (autostart), reglas de ufw, busybox y `gns3_server.conf`.
2. Abrir la GUI de GNS3 → **File → Open project → ACC-Lab**.
3. **▶ Start all** (los nodos «en espera» del Site B —portal-b, authelia-b, gate-b, archivo-b— se dejan parados).
   Atajo por terminal (con la GUI abierta): pedir al agente «arranca el laboratorio».
4. Esperar ≈3 min (arranque de los OPNsense) y ejecutar:
   ```bash
   bash scripts/lab-check.sh
   ```
5. Si algo sale en rojo:

| Fallo | Causa habitual | Solución |
|---|---|---|
| fw-a1 MASTER de 0/8 VIP | demotion de CARP por pfsync al arrancar | `bash scripts/fw.sh fw-a1 'sysctl net.inet.carp.demotion=-240'` |
| Portal público 502/530 | el túnel arrancó antes que la WAN o quedó con conexiones muertas | reiniciar el nodo `cloudflared-a` |
| OSPF A↔B < 2 túneles | el DPD tarda en reconectar | esperar 1 min; si no, `bash scripts/opn-apply.sh fw-b strongswan` |
| Authelia no arrancada | arrancó antes que portal-db o dc1 | se reintenta sola cada 10 s; si no, reiniciar el nodo `authelia` |
| Un switch con puertos sin enlace | fallo de cableado de GNS3 3.1 alfa | ver AGENTS.md (13): detener, rehacer enlaces, arrancar |
| Error `brctl vlan_add` al abrir | (ya no debería ocurrir: los switches integrados se sustituyeron por OVS) | `sudo ip link set <bridge>-0 master <bridge>; sudo bridge vlan add dev <bridge>-0 vid 1 pvid untagged` |

## Buenas prácticas
- En **File → Edit project**, «Leave this project running in the background when closing GNS3» permite cerrar la GUI **sin** apagar el laboratorio (útil durante el día). Para apagar el equipo, en cambio, cerrar el proyecto como en el paso 1.
- No borrar ni cambiar adaptadores de nodos en marcha (AGENTS.md 13 y 15).
