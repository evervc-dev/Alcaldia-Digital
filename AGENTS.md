# Reglas para agentes IA — Alcaldia-Digital

1. **Antes de nada lee `ESTADO.md`** (fase actual, nodos encendidos, errores conocidos) y la bitácora del día en `docs/bitacora/`.
2. **Un solo agente a la vez.** No abras consolas de GNS3 si otro agente está trabajando.
3. **Cambios en GNS3 solo con `gns3-mcp`** (project/node/link/console/node_file). Excepciones: `scripts/gns3-templates.sh` (crea plantillas, gns3-mcp no puede) y `docker exec` desde el host **solo para inspeccionar o configurar dentro** de contenedores ya creados por GNS3 (nunca crear ni borrar contenedores con docker). Para OPNsense, la consola telnet del MCP; para la pantalla VGA, `scripts/qemu-monitor.py`.
4. **Secretos:** solo en `.env` (ignorado por git). Nunca escribas contraseñas, tokens ni claves en archivos versionados, en commits ni en la bitácora. El repo es público.
5. **Direcciones IP y VLAN:** la fuente única es `inventory/ipam.md`. Si cambias algo, actualízalo ahí primero.
6. **Persistencia:** en nodos Docker solo sobreviven `/etc/network` y los `VOLUME` de la imagen (verificado en F0, ver `docs/pruebas/F0-canario.md`). No guardes estado fuera de esos directorios.
7. **RAM:** el laboratorio no debe superar 12 GB. Arranca solo lo que la fase necesita y revisa `free -g`.
8. **Plan B inmediato:** si CARP + IPsec VTI falla al primer intento, termina los túneles en la IP propia de cada FW y deja que OSPF elija. Anótalo en la bitácora y sigue.
9. **MVP primero** (ver PLAN_DESARROLLO.md §8.0). No empieces extras (Suricata, GLPI, oxidized, cinta) sin terminar el MVP.
10. **Cierre de fase:** actualiza `ESTADO.md`, añade a la bitácora (acciones, errores y su solución), haz commit (`Fx: ...`) y push.
11. **Errores:** todo error con su causa y su solución va a la bitácora, para no repetirlo.
12. **Cambios en equipos redundantes, de uno en uno:** verificar el primero (enlace, LACP, ping) **antes** de tocar el segundo.
13. **GNS3 3.1 alfa:** cambiar `adapters` de un nodo Docker lo recrea **sin volver a cablear sus enlaces**. Hay que detenerlo, borrar sus enlaces (la API da error pero borra), volver a crearlos y arrancarlo. Cambiar la imagen exige recrear el nodo.
14. Las salidas de `wbinfo`/`smbclient` pueden mostrar `usuario%contraseña`: filtrar siempre (`grep -v %`).
15. **Detener un nodo antes de borrarlo:** si se borra en marcha, el puerto del switch queda ocupado por un enlace fantasma ("Port is already used").
