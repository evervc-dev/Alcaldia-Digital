#!/bin/sh
# Cinta LTO simulada (equivale a la librería LTO de la Fase 4): al ENCENDER el nodo 'tape' copia el contenido
# de nas-b (bucket respaldos: repositorio restic cifrado + configuraciones) a un "cartucho" fechado en su volumen.
# Después el operador APAGA el nodo: fuera de línea (air gap), ningún ransomware ni borrado remoto lo alcanza.
set -a; . /data/.acc/cinta.env; set +a
C=/data/cartuchos/$(date +%Y-%m-%d_%H%M); mkdir -p "$C"; LOG=/data/cartuchos/registro.log
# el alias se registra DENTRO del bucle: «mc alias set» comprueba el servidor y, si nas-b aún arranca, no lo guarda
conecta() { timeout 15 mc alias set nasb "http://$NAS_B:9000" restic-lectura "$CLAVE_LECTURA" >/dev/null 2>&1 && timeout 15 mc ls nasb/respaldos >/dev/null 2>&1; }
t0=$(date +%s)
until conecta; do sleep 10; [ $(( $(date +%s) - t0 )) -gt 600 ] && { echo "$(date -Iseconds) FALLO: nas-b no responde" >> $LOG; exit 1; }; done
if mc mirror --quiet nasb/respaldos "$C" >/dev/null 2>&1; then
  echo "$(date -Iseconds) OK cartucho $(basename $C): $(find "$C" -type f | wc -l) objetos, $(du -sh "$C" | cut -f1), $(( $(date +%s) - t0 )) s. Ya puede APAGAR el nodo tape." >> $LOG
else echo "$(date -Iseconds) FALLO copiando a $(basename $C)" >> $LOG; fi
tail -1 $LOG
