#!/bin/bash
# GLPI (mesa de servicio, mesa.evervc.dev): configuración completa e idempotente. Nunca imprime secretos.
#  1) SQL (glpi-db): API solo desde la VLAN SERVIDORES, idioma, URL pública, SSO por cabecera Remote-User
#     (la fija nginx-dmz tras Authelia + horario), correo a mailpit, contraseña de 'glpi', cuentas de ejemplo desactivadas.
#  2) API REST (desde el contenedor portal): directorio AD por LDAPS (dc1 + réplica dc2), reglas de perfil por grupo
#     del AD (mesa-tecnicos -> Technician, mesa-admins -> Admin; el resto Self-Service), usuario 'zabbix' y categoría.
#  3) SQL: el directorio AD completa los datos de los usuarios SSO; se limpia la caché.
# Requiere: nodos glpi y glpi-db en marcha (services-setup.sh ya entregó glpi.env / db.env).
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
C() { echo "GNS3.$1.$PID"; }
sql() { docker exec -i -e MYSQL_PWD="$GLPI_DB_ROOT_PASS" "$(C glpi-db)" mariadb -uroot -N glpi; }
for i in $(seq 1 60); do echo 'select 1 from glpi_configs limit 1' | sql >/dev/null 2>&1 && break; sleep 5; done

# ---------- 1) SQL ----------
HASH=$(docker exec -e P="$GLPI_ADMIN_PASS" "$(C glpi)" php -r 'echo password_hash(getenv("P"), PASSWORD_DEFAULT);')
cfg() { printf "INSERT INTO glpi_configs (context,name,value) VALUES ('core','%s','%s') ON DUPLICATE KEY UPDATE value=VALUES(value);\n" "$1" "$2"; }
{
  echo "UPDATE glpi_apiclients SET name='VLAN SERVIDORES (Zabbix, glpi-setup)', is_active=1, app_token=NULL,
        ipv4_range_start=INET_ATON('10.10.20.0'), ipv4_range_end=INET_ATON('10.10.20.255') WHERE id=1;"
  cfg enable_api 1; cfg enable_api_login_credentials 1; cfg enable_api_login_external_token 0
  cfg url_base 'https://mesa.evervc.dev'; cfg url_base_api 'https://mesa.evervc.dev/apirest.php'
  cfg language es_ES; cfg timezone 'America/El_Salvador'   # vista en hora local (la BD guarda UTC)
  cfg ssovariables_id "$(echo "select id from glpi_ssovariables where name='HTTP_REMOTE_USER'" | sql)"
  cfg is_users_auto_add 1; cfg ssologout_url 'https://auth.evervc.dev/logout'
  cfg use_notifications 1; cfg notifications_mailing 1; cfg smtp_mode 1; cfg smtp_host 10.10.20.32; cfg smtp_port 1025
  cfg smtp_check_certificate 0; cfg admin_email 'mesa@alcaldia.lab'; cfg admin_email_name 'Mesa de servicio - Alcaldía Digital'
  cfg from_email 'mesa@alcaldia.lab'; cfg from_email_name 'Mesa de servicio - Alcaldía Digital'; cfg noreply_email 'no-reply@alcaldia.lab'
  echo "UPDATE glpi_users SET password='$HASH', password_last_update=NOW() WHERE name='glpi';"
  echo "UPDATE glpi_users SET is_active=0 WHERE name IN ('tech','normal','post-only');"
  echo "GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'%';"   # GLPI necesita leer las zonas horarias para mostrar hora local
} | sql
echo "SQL: API (solo 10.10.20.0/24), español, URL pública, SSO Remote-User, correo -> mailpit, 'glpi' con contraseña del .env, cuentas de ejemplo desactivadas"

# ---------- 2) API ----------
docker exec -i -e GLPI_ADMIN_PASS -e GLPI_ZABBIX_PASS -e GLPI_PORTAL_PASS -e SVC_LDAP_PASS "$(C portal)" python3 - <<'PY'
import base64, json, os, urllib.request, urllib.error
U = "http://10.10.20.31/apirest.php"
def call(method, path, body=None, auth=None):
    h = {"Content-Type": "application/json"}
    if auth: h["Authorization"] = auth
    else: h["Session-Token"] = TOK
    r = urllib.request.Request(U + path, json.dumps(body).encode() if body is not None else None, h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            t = f.read(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"API {method} {path}: {e.code} {e.read()[:300]!r}")
TOK = call("GET", "/initSession", auth="Basic " + base64.b64encode(b"glpi:" + os.environ["GLPI_ADMIN_PASS"].encode()).decode())["session_token"]

def find(itemtype, **flt):
    for it in call("GET", f"/{itemtype}?range=0-999&expand_dropdowns=false") or []:
        if all(str(it.get(k)) == str(v) for k, v in flt.items()): return it
def upsert(itemtype, key, data):
    it = find(itemtype, **key)
    if it:
        call("PUT", f"/{itemtype}/{it['id']}", {"input": data}); return it["id"]
    return call("POST", f"/{itemtype}", {"input": {**key, **data}})["id"]

BASE = "DC=ad,DC=alcaldia,DC=lab"
ldap = upsert("AuthLDAP", {"name": "AD alcaldia.lab (dc1)"}, {
    "host": "ldaps://10.10.20.10", "port": 636, "basedn": BASE, "use_dn": 1,
    "rootdn": "svc-lectura@ad.alcaldia.lab", "rootdn_passwd": os.environ["SVC_LDAP_PASS"],
    "condition": "(&(objectClass=user)(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))",
    "login_field": "samaccountname", "sync_field": "objectguid", "email1_field": "mail",
    "realname_field": "sn", "firstname_field": "givenname", "title_field": "title",
    "group_search_type": 0, "group_field": "memberof", "group_condition": "(objectClass=group)", "group_member_field": "member",
    "is_active": 1, "is_default": 1, "timeout": 5, "comment": "Directorio del AD (LDAPS con la CA del laboratorio). Gestionado por glpi-setup.sh"})
upsert("AuthLdapReplicate", {"authldaps_id": ldap, "name": "dc2 (Site B)"}, {"host": "ldaps://10.20.20.10", "port": 636, "timeout": 5})
print(f"API: directorio AD id={ldap} (dc1 + réplica dc2, LDAPS)")

PROF = {p["name"]: p["id"] for p in call("GET", "/Profile?range=0-50")}
for nombre, grupo, perfil in (("ACC: técnicos de la mesa (AD mesa-tecnicos)", "mesa-tecnicos", "Technician"),
                              ("ACC: administradores de la mesa (AD mesa-admins)", "mesa-admins", "Admin")):
    rid = upsert("RuleRight", {"name": nombre}, {"sub_type": "RuleRight", "match": "AND", "is_active": 1, "entities_id": 0,
                                              "is_recursive": 1, "description": f"Perfil {perfil} para el grupo {grupo} del AD"})
    for c in call("GET", f"/RuleRight/{rid}/RuleCriteria") or []: call("DELETE", f"/RuleCriteria/{c['id']}")
    for a in call("GET", f"/RuleRight/{rid}/RuleAction") or []: call("DELETE", f"/RuleAction/{a['id']}")
    call("POST", "/RuleCriteria", {"input": {"rules_id": rid, "criteria": "memberof", "condition": 2,
                                              "pattern": f"CN={grupo},CN=Users,{BASE}"}})
    for f, v in (("profiles_id", PROF[perfil]), ("entities_id", 0), ("is_recursive", 1), ("_profiles_id_default", PROF[perfil])):
        call("POST", "/RuleAction", {"input": {"rules_id": rid, "action_type": "assign", "field": f, "value": v}})
    print(f"API: regla «{grupo}» -> perfil {perfil}")

zu = find("User", name="zabbix")   # la contraseña solo al crear: GLPI rechaza reutilizarla (historial de contraseñas)
datos = {"realname": "Zabbix", "firstname": "Monitoreo", "is_active": 1, "comment": "Cuenta de servicio: Zabbix abre y cierra tickets por la API"}
if zu: call("PUT", f"/User/{zu['id']}", {"input": datos}); zid = zu["id"]
else: zid = call("POST", "/User", {"input": {"name": "zabbix", **datos, "password": os.environ["GLPI_ZABBIX_PASS"],
                                              "password2": os.environ["GLPI_ZABBIX_PASS"]}})["id"]
pus = call("GET", f"/User/{zid}/Profile_User") or []
if not any(str(pu.get("profiles_id")) == str(PROF["Technician"]) for pu in pus):
    call("POST", "/Profile_User", {"input": {"users_id": zid, "profiles_id": PROF["Technician"], "entities_id": 0, "is_recursive": 1}})
for pu in pus:   # GLPI le añade Self-Service al crearlo: la sesión API entraría con él y no podría resolver tickets
    if str(pu.get("profiles_id")) != str(PROF["Technician"]): call("DELETE", f"/Profile_User/{pu['id']}")
call("PUT", f"/User/{zid}", {"input": {"profiles_id": PROF["Technician"]}})   # perfil por defecto
# Cuenta de servicio del portal (Self-Service): cada reporte ciudadano de /reportar abre un ticket P4 (Fase 4 §2.2)
pu = find("User", name="portal")
dp = {"realname": "Portal ciudadano", "firstname": "Reportes", "is_active": 1, "comment": "Cuenta de servicio: el portal abre tickets P4 por la API"}
if pu: call("PUT", f"/User/{pu['id']}", {"input": dp}); pid_ = pu["id"]
else: pid_ = call("POST", "/User", {"input": {"name": "portal", **dp, "password": os.environ["GLPI_PORTAL_PASS"],
                                               "password2": os.environ["GLPI_PORTAL_PASS"]}})["id"]
if not any(str(x.get("profiles_id")) == str(PROF["Self-Service"]) for x in call("GET", f"/User/{pid_}/Profile_User") or []):
    call("POST", "/Profile_User", {"input": {"users_id": pid_, "profiles_id": PROF["Self-Service"], "entities_id": 0, "is_recursive": 1}})
print("API: usuario portal (Self-Service) y categoría «Portal ciudadano: reporte de falla»")
cat = upsert("ITILCategory", {"name": "Infraestructura (alerta de Zabbix)"}, {"comment": "Tickets abiertos automáticamente por el monitoreo",
                                                                            "is_helpdeskvisible": 0})
print(f"API: usuario zabbix (Technician), categoría {cat}")
# ---------- Catálogo (Fase 4 Tablas 1 y 2), horario, SLA (Tabla 6) y reglas ----------
# Prioridad GLPI (matriz urgencia x impacto) <-> Fase 4: 5 = P1, 4 = P2, 3 = P3, 1-2 = P4
def categoria(nombre, padre=0, inc=1, req=1, visible=1, comentario=""):
    c = find("ITILCategory", name=nombre)
    d = {"itilcategories_id": padre, "is_incident": inc, "is_request": req, "is_helpdeskvisible": visible, "comment": comentario}
    if c: call("PUT", f"/ITILCategory/{c['id']}", {"input": d}); return c["id"]
    return call("POST", "/ITILCategory", {"input": {"name": nombre, **d}})["id"]
CAT = {}
for sid, nom, resp in (("S1", "Identidad centralizada", "Jefe de Servicios y Aplicaciones"), ("S2", "Portal de trámites", "Jefe de Servicios y Aplicaciones"),
                       ("S3", "Archivo digital", "Jefe de Servicios y Aplicaciones"), ("S4", "Monitoreo", "Jefe de Soporte y Monitoreo"),
                       ("S5", "Mesa de servicio", "Jefe de Soporte y Monitoreo"), ("S6", "Respaldos", "Jefe de Continuidad y Respaldos"),
                       ("SEDE", "Kit de sede y conectividad", "Jefe de Infraestructura y Redes")):
    CAT[sid] = categoria(f"{sid} {nom}" if sid != "SEDE" else nom, comentario=f"Catálogo de servicios (Fase 4, Tabla 1). Responsable: {resp}")
SOL = {   # solicitudes estándar (Tabla 2): nombre -> (servicio, prioridad GLPI)
    "Alta, baja o cambio de rol de una cuenta": ("S1", 2), "Restablecimiento de contraseña o del segundo factor": ("S1", 3),
    "Restauración de un documento o archivo": ("S3", 3), "Alta de un trámite en el portal (cambio normal, CAB)": ("S2", 2),
    "Revisión o reemplazo del kit de la sede": ("SEDE", 3)}
for nom, (sid, _) in SOL.items():
    CAT[nom] = categoria(nom, CAT[sid], inc=0, req=1, comentario="Solicitud estándar (Fase 4, Tabla 2): cambio preaprobado")
categoria("Portal ciudadano: reporte de falla", CAT["S2"], inc=1, req=0, comentario="Reportes de la ciudadanía desde portal.evervc.dev/reportar (P4)")
categoria("Infraestructura (alerta de Zabbix)", CAT["S4"], inc=1, req=0, visible=0, comentario="Tickets abiertos automáticamente por el monitoreo")

cal = find("Calendar", name="Mesa de servicio L-V 07:00-19:00")
cal = cal["id"] if cal else call("POST", "/Calendar", {"input": {"name": "Mesa de servicio L-V 07:00-19:00", "is_recursive": 1,
                                                                   "comment": "Horario de la mesa (Fase 1 §3.4, Fase 4 §5)"}})["id"]
if not (call("GET", f"/Calendar/{cal}/CalendarSegment") or []):
    for d in range(1, 6):
        call("POST", "/CalendarSegment", {"input": {"calendars_id": cal, "day": d, "begin": "07:00:00", "end": "19:00:00", "is_recursive": 1}})

def slm(nombre, calendario, comentario):
    s = find("SLM", name=nombre); d = {"calendars_id": calendario, "is_recursive": 1, "comment": comentario}
    if s: call("PUT", f"/SLM/{s['id']}", {"input": d}); return s["id"]
    return call("POST", "/SLM", {"input": {"name": nombre, **d}})["id"]
SLM_24 = slm("Mesa: P1 (guardia 24x7)", 0, "P1: el tiempo corre siempre; fuera de horario lo atiende la guardia (Fase 4 §2.2 y §5.3)")
SLM_LV = slm("Mesa: P2-P4 (L-V 07:00-19:00)", cal, "P2 a P4: en el horario de la mesa (Fase 4 Tabla 6)")
SLA = {}
for p, s_, (tto, tto_u), (ttr, ttr_u) in (("P1", SLM_24, (15, "minute"), (4, "hour")), ("P2", SLM_LV, (30, "minute"), (8, "hour")),
                                          ("P3", SLM_LV, (2, "hour"), (24, "hour")), ("P4", SLM_LV, (8, "hour"), (72, "hour"))):
    for tipo, n, u, et in ((1, tto, tto_u, "respuesta"), (0, ttr, ttr_u, "resolución")):
        nombre = f"{p} {et} {n} {'min' if u == 'minute' else 'h'}"
        SLA[(p, tipo)] = upsert("SLA", {"name": nombre}, {"slms_id": s_, "type": tipo, "number_time": n, "definition_time": u,
                                                          "end_of_working_day": 0, "is_recursive": 1})

def regla(nombre, criterios, acciones, rank, desc):
    rid = upsert("RuleTicket", {"name": nombre}, {"sub_type": "RuleTicket", "match": "AND", "is_active": 1, "entities_id": 0,
                                                 "is_recursive": 1, "condition": 3, "ranking": rank, "description": desc})
    for c in call("GET", f"/RuleTicket/{rid}/RuleCriteria") or []: call("DELETE", f"/RuleCriteria/{c['id']}")
    for a in call("GET", f"/RuleTicket/{rid}/RuleAction") or []: call("DELETE", f"/RuleAction/{a['id']}")
    for crit, cond, pat in criterios:
        call("POST", "/RuleCriteria", {"input": {"rules_id": rid, "criteria": crit, "condition": cond, "pattern": pat}})
    for campo, val in acciones:
        call("POST", "/RuleAction", {"input": {"rules_id": rid, "action_type": "assign", "field": campo, "value": val}})
# 1) prioridad de las solicitudes estándar (antes que las de SLA)
for k, (nom, (sid, prio)) in enumerate(SOL.items()):
    regla(f"ACC: prioridad de «{nom}»", [("itilcategories_id", 0, CAT[nom])], [("urgency", prio), ("impact", prio), ("priority", prio)],
          10 + k, f"Solicitud estándar (Fase 4 Tabla 2): prioridad {'P4' if prio <= 2 else 'P3'}")
# 2) SLA según la prioridad. El criterio «prioridad» es una lista: solo admite «es» (condición 0), no expresiones
#    regulares -> una regla por valor (6 y 5 = P1, 4 = P2, 3 = P3, 2 y 1 = P4)
for viejo in ("ACC: SLA P1", "ACC: SLA P2", "ACC: SLA P3", "ACC: SLA P4"):
    r = find("RuleTicket", name=viejo)
    if r: call("DELETE", f"/RuleTicket/{r['id']}")
for k, (prio, p) in enumerate(((6, "P1"), (5, "P1"), (4, "P2"), (3, "P3"), (2, "P4"), (1, "P4"))):
    regla(f"ACC: SLA {p} (prioridad {prio})", [("priority", 0, str(prio))], [("slas_id_tto", SLA[(p, 1)]), ("slas_id_ttr", SLA[(p, 0)])],
          50 + k, f"Fase 4 Tabla 6: tiempos de respuesta y resolución de {p}")
print(f"API: catálogo S1-S6 + {len(SOL)} solicitudes estándar, calendario L-V 07-19, 8 SLA (P1 24x7) y reglas de prioridad/SLA")
call("GET", "/killSession")
open("/tmp/glpi-ldap-id", "w").write(str(ldap))
PY

# ---------- 3) SQL ----------
LID=$(docker exec "$(C portal)" cat /tmp/glpi-ldap-id)
{ cfg authldaps_id_extra "$LID"; cfg existing_auth_server_field_clean_domain 1; } | sql
docker exec "$(C glpi)" setpriv --reuid=www-data --regid=www-data --init-groups -- php /var/www/glpi/bin/console database:enable_timezones -n -q >/dev/null 2>&1 || true
docker exec "$(C glpi)" setpriv --reuid=www-data --regid=www-data --init-groups -- php /var/www/glpi/bin/console cache:clear -q >/dev/null 2>&1 || true
echo "SSO: datos de usuario desde el directorio AD id=$LID; caché limpiada. Listo: https://mesa.evervc.dev"
