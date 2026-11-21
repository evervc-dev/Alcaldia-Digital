# F0 — Canario de persistencia y viabilidad (2026-11-21)

Proyecto temporal `ACC-Canario` con: `canario` (ACC-PC), `sw-test` (ACC-OVS), `nginx-bond` (ACC-Nginx, imagen oficial) y `fw-test` (ACC-OPNsense).

| # | Prueba | Resultado | Evidencia |
|---|---|---|---|
| 1 | `VOLUME` de la imagen persiste al cerrar y reabrir el proyecto | ✅ | `/data/canary.txt` = `persistente-1795283502` tras reabrir; en el host: `project-files/docker/<node-id>/data/` |
| 2 | Archivo fuera de un VOLUME se pierde (contenedor recreado) | ✅ (esperado) | `/root/efimero.txt` → "No such file" |
| 3 | `/etc/network/interfaces` persiste | ✅ | Configuración de bond0 intacta tras reabrir |
| 4 | Bond active-backup en imagen propia (iproute2) | ✅ | `Bonding Mode: fault-tolerance (active-backup)`; failover eth0→eth1 con 0 % de pérdida |
| 5 | Bond en imagen **oficial** solo con busybox (nginx:1.27-alpine) | ✅ | Mismo método: `ip link add bond0 type bond` + sysfs (`bonding/mode`, `bonding/slaves`) en `pre-up` |
| 6 | Conectividad entre nodos con bond a través de OVS | ✅ | ping 10.99.0.10 → 10.99.0.20, ~1.3 ms |
| 7 | OVS: VLAN de acceso persiste (`/etc/openvswitch/conf.db`) | ✅ | `tag: 10` en eth3 tras reabrir. Nota: datapath `netdev` (espacio de usuario), todos los puertos en `br0` por defecto |
| 8 | OPNsense 26.7 nano arranca con KVM | ✅ (tras corrección) | `login:` en la consola serie ttyu0 |

## Hallazgos y correcciones
- **GNS3 3.1.0a6 no conecta el disco QEMU** si la plantilla no define `hda_disk_interface` (aparece `-drive ... if=none` sin `-device`) → "No bootable device". **Solución:** `hda_disk_interface: sata` en la plantilla ACC-OPNsense.
- **OPNsense nano tiene consola serie primaria** ("Dual Console: Serial Primary") → plantilla con `console_type: telnet`; se automatiza por gns3-mcp `console`. Para la pantalla VGA queda `scripts/qemu-monitor.py` (screendump/sendkey por el monitor de QEMU).
- Si OPNsense no ha terminado de arrancar, ignora el apagado ACPI y GNS3 tarda unos 2 min en forzarlo; esto bloquea `project close`. Conviene esperar a `login:` antes de cerrar.
- Con el canal TCP de uBridge y busybox estático en el host, todos los nodos arrancan.

## Patrón de red para servidores Tier II (bond A/B)
```
auto bond0
iface bond0 inet static
	pre-up ip link add bond0 type bond 2>/dev/null || true
	pre-up echo active-backup > /sys/class/net/bond0/bonding/mode; echo 100 > /sys/class/net/bond0/bonding/miimon
	pre-up ip link set eth0 down; ip link set eth1 down; echo +eth0 > /sys/class/net/bond0/bonding/slaves; echo +eth1 > /sys/class/net/bond0/bonding/slaves
	address <IP>
	netmask 255.255.255.0
	gateway <GW>
```
