#!/bin/bash
# Política de horario laboral en el escritorio (ts1). Se ejecuta al iniciar la sesión (startwm.sh).
# Fuente: /etc/acc/horario.conf (config/politicas/horario.conf). Pertenencia a grupos: AD vía winbind.
# Sale 0 si puede continuar; si no, muestra el motivo, registra y sale 1 (startwm.sh cierra la sesión).
GRUPO_RESTRINGIDO=funcionarios; GRUPO_EXENTO=acceso-24h; DIAS=1,2,3,4,5; DESDE=08:00; HASTA=16:00; TZ_OFFSET=-6
[ -f /etc/acc/horario.conf ] && . <(sed 's/#.*//' /etc/acc/horario.conf)
U=$(id -un); G=" $(id -nG "$U" 2>/dev/null | tr 'A-Z' 'a-z') "
log() { echo "$(date -Is) user=$U $1" >> /var/log/acc-horario.log; }
case "$G" in *" ${GRUPO_EXENTO,,} "*) log "permitido (exento: $GRUPO_EXENTO)"; exit 0 ;; esac
case "$G" in *" ${GRUPO_RESTRINGIDO,,} "*) ;; *) log "permitido (sin restricción)"; exit 0 ;; esac
H=$(TZ="UTC$(( -TZ_OFFSET ))" date +%H:%M); D=$(TZ="UTC$(( -TZ_OFFSET ))" date +%u); HOY=$(TZ="UTC$(( -TZ_OFFSET ))" date '+%A %d/%m/%Y %H:%M')
if [[ ",$DIAS," == *",$D,"* && ! "$H" < "$DESDE" && "$H" < "$HASTA" ]]; then log "permitido (dentro de horario)"; exit 0; fi
log "DENEGADO fuera de horario ($HOY)"
MSG="Acceso fuera del horario laboral\n\nLa cuenta <b>$U</b> (grupo $GRUPO_RESTRINGIDO) solo puede usar su escritorio\nde <b>lunes a viernes, de $DESDE a $HASTA</b> (hora de El Salvador).\n\nHora actual: $HOY\n\nSi necesita acceso fuera de este horario, contacte a la Mesa de Servicio.\nLa sesión se cerrará al aceptar."
zenity --error --title="Alcaldía Digital · Horario laboral" --width=520 --text="$MSG" 2>/dev/null \
  || xfce4-terminal --hide-menubar -T "Horario laboral" -x sh -c "printf '$MSG\n'; sleep 30"
exit 1
