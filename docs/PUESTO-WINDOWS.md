# Puesto Windows unido al dominio (plantilla QEMU para la defensa)

## Requisitos de la plantilla
- **Edición:** Windows 10/11 **Pro, Enterprise o Education** (la Home no se une a dominios). Windows 11 Enterprise de evaluación (90 días) sirve.
- **Hardware QEMU en GNS3:** 4 GB de RAM, 2 vCPU, disco SATA, **NIC e1000** (Windows la reconoce sin controladores extra). Si se usa virtio, hay que instalar `virtio-win`.
- **Red:** conectar el puerto de red a un puerto libre del switch de una sede (p. ej. `sw-sede-02`): recibe IP por **DHCP del kit**, con DNS **dc1/dc2** y dominio de búsqueda `ad.alcaldia.lab`.

## Unión al dominio (una sola vez, ya lo dejas hecho en la plantilla)
1. Comprobar resolución: `nslookup -type=SRV _ldap._tcp.ad.alcaldia.lab` debe devolver dc1/dc2.
2. *Configuración → Sistema → Acerca de → Dominio o grupo de trabajo → Cambiar* → **Dominio:** `ad.alcaldia.lab`.
3. Credenciales con permiso para unir equipos: `ALCALDIA\administrator` o `ALCALDIA\admin.dc` (Domain Admins). Reiniciar.
4. En la pantalla de inicio: **Otro usuario** → `ALCALDIA\tecnico.soporte` (o cualquier usuario creado en LAM).

## Hora (Kerberos admite como máximo 5 min de diferencia)
El DC de Samba no sirve NTP firmado, así que en el puesto: `w32tm /config /manualpeerlist:"pool.ntp.org" /syncfromflags:manual /update` (la sede tiene Internet por su ISP).

## Horario laboral en Windows (se hará cuando exista el puesto)
Windows no ejecuta `horario.sh`. Opciones (a decidir):
- **Script de inicio de sesión** en `\\ad.alcaldia.lab\NETLOGON\horario.ps1`, asignado a los usuarios de `funcionarios` (atributo `scriptPath`): consulta `config/politicas/horario.conf` y, fuera de horario, muestra el mensaje y cierra la sesión — mismo comportamiento que en Linux.
- `logonHours` solo para los puestos Windows: Windows **sí** muestra el motivo («Su cuenta tiene restricciones de tiempo…»), pero afecta a todos los servicios de esa cuenta.

## Firewall
Ya permitido desde las sedes y la VLAN USUARIOS hacia dc1/dc2 (`PUERTOS_AD_CLIENTE`). No hace falta tocar nada más.
