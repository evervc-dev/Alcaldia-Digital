#!/usr/bin/env python3
"""
F8 — Configura Zabbix 7.0 por API (idempotente). Lo lanza scripts/zbx-setup.sh DENTRO del contenedor 'portal'
(Python 3 en la VLAN SERVIDORES). Secretos solo por variables de entorno (desde .env); no se imprimen.

Qué crea:
  - Grupos ACC/Site A, ACC/Site B, ACC/Sedes, ACC/Enlaces WAN, ACC/Internet.
  - Hosts con plantilla "ICMP Ping" (equipo caído) + comprobaciones de servicio (puerto/HTTP) con disparadores.
  - Kits de sede por SNMP ("Linux by SNMP" + estado de los 3 túneles IPsec y vecinos OSPF).
  - Réplica del portal en el Site B: antigüedad por ODBC (RPO 1 h), NAS: % ocupado (métricas MinIO).
  - Escenario web del portal público https://portal.evervc.dev (ruta completa Cloudflare -> túnel -> DMZ).
  - Alertas por correo a mailpit (ti@alcaldia.lab), tickets en GLPI (webhook) y mapa de red "Alcaldía Digital".
"""
import json, os, sys, urllib.request

URL = os.environ.get("ZBX_URL", "http://10.10.20.33:8080/api_jsonrpc.php")
ADMIN_PASS = os.environ["ZABBIX_ADMIN_PASS"]
SNMP_COMM = os.environ["ZBX_SNMP_COMMUNITY"]
PORTAL_DB_PASS = os.environ["PORTAL_DB_PASS"]
TOKEN = None


def api(method, params, auth=True):
    body = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json-rpc"})
    if auth and TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    r = json.load(urllib.request.urlopen(req, timeout=30))
    if "error" in r:
        raise RuntimeError(f"{method}: {r['error'].get('data') or r['error']}")
    return r["result"]


# ---------- sesión (cambia la contraseña por defecto la primera vez) ----------
try:
    TOKEN = api("user.login", {"username": "Admin", "password": ADMIN_PASS}, auth=False)
except RuntimeError:
    TOKEN = api("user.login", {"username": "Admin", "password": "zabbix"}, auth=False)
    uid = api("user.get", {"filter": {"username": "Admin"}, "output": ["userid"]})[0]["userid"]
    api("user.update", {"userid": uid, "current_passwd": "zabbix", "passwd": ADMIN_PASS})
    TOKEN = api("user.login", {"username": "Admin", "password": ADMIN_PASS}, auth=False)
    print("Admin: contraseña por defecto reemplazada (valor en .env)")

# ---------- macro global con la comunidad SNMP (tipo secreto) ----------
m = api("usermacro.get", {"globalmacro": True, "filter": {"macro": "{$SNMP_COMMUNITY}"}})
if m:
    api("usermacro.updateglobal", {"globalmacroid": m[0]["globalmacroid"], "value": SNMP_COMM, "type": 1})
else:
    api("usermacro.createglobal", {"macro": "{$SNMP_COMMUNITY}", "value": SNMP_COMM, "type": 1})


def group(name):
    g = api("hostgroup.get", {"filter": {"name": [name]}})
    return g[0]["groupid"] if g else api("hostgroup.create", {"name": name})["groupids"][0]


def template(name):
    return api("template.get", {"filter": {"host": [name]}, "output": ["templateid"]})[0]["templateid"]


G = {k: group(f"ACC/{k}") for k in ("Site A", "Site B", "Sedes", "Enlaces WAN", "Internet")}
T_ICMP, T_SNMP = template("ICMP Ping"), template("Linux by SNMP")
for it in api("item.get", {"templateids": [T_ICMP, T_SNMP], "search": {"key_": "icmpping"}, "output": ["itemid", "delay"]}):
    if it["delay"] != "20s":
        api("item.update", {"itemid": it["itemid"], "delay": "20s"})   # detección de caída en ~1 min (3 x 20 s)


def host(name, ip, grp, snmp=False, desc=""):
    templates = [{"templateid": T_SNMP if snmp else T_ICMP}]   # "Linux by SNMP" ya incluye el ping ICMP
    if ip:
        iface = ({"type": 2, "main": 1, "useip": 1, "ip": ip, "dns": "", "port": "161",
                  "details": {"version": 2, "bulk": 1, "community": "{$SNMP_COMMUNITY}"}} if snmp else
                 {"type": 1, "main": 1, "useip": 1, "ip": ip, "dns": "", "port": "10050"})
    h = api("host.get", {"filter": {"host": [name]}, "output": ["hostid"], "selectInterfaces": ["interfaceid"]})
    if h:
        hid = h[0]["hostid"]
        api("host.update", {"hostid": hid, "groups": [{"groupid": G[grp]}], "description": desc,
                            "templates": templates if ip else []})
    else:
        p = {"host": name, "groups": [{"groupid": G[grp]}], "description": desc}
        if ip:
            p.update(interfaces=[iface], templates=templates)
        hid = api("host.create", p)["hostids"][0]
    ifs = api("hostinterface.get", {"hostids": hid, "output": ["interfaceid", "ip"]})
    if ifs and ip and ifs[0]["ip"] != ip:   # la IP cambió (p. ej. GUI de los FW solo en ADMIN desde T5)
        api("hostinterface.update", {"interfaceid": ifs[0]["interfaceid"], "ip": ip})
    return hid, (ifs[0]["interfaceid"] if ifs else None)


def item(hid, ifid, name, key, **kw):
    it = api("item.get", {"hostids": hid, "filter": {"key_": key}, "output": ["itemid"]})
    p = {"name": name, "key_": key, "delay": kw.pop("delay", "30s"), "value_type": kw.pop("value_type", 3)}
    p.update(kw)
    if ifid and p.get("type") in (3, 20):
        p["interfaceid"] = ifid
    if it:
        p.pop("value_type"); api("item.update", {"itemid": it[0]["itemid"], **p}); return it[0]["itemid"]
    return api("item.create", {"hostid": hid, **p})["itemids"][0]


def trigger(hid, desc, expr, prio, comments=""):
    t = api("trigger.get", {"hostids": hid, "filter": {"description": desc}, "output": ["triggerid"]})
    p = {"description": desc, "expression": expr, "priority": prio, "comments": comments}
    if t:
        api("trigger.update", {"triggerid": t[0]["triggerid"], **p}); return t[0]["triggerid"]
    return api("trigger.create", p)["triggerids"][0]


SEV = {"info": 1, "warning": 2, "average": 3, "high": 4, "disaster": 5}
HOSTS = {}       # nombre -> hostid (para el mapa)
TRIG = {}        # clave -> triggerid (para colorear enlaces del mapa)


def servicios(name, ip, grp, checks, desc="", snmp=False):
    """checks: [(etiqueta, protocolo 'tcp'|'http'|..., puerto)]"""
    hid, ifid = host(name, ip, grp, snmp=snmp, desc=desc)
    HOSTS[name] = hid
    keep = {f"net.tcp.service[{proto},{ip},{port}]" for _, proto, port in checks}
    stale = [i["itemid"] for i in api("item.get", {"hostids": hid, "search": {"key_": "net.tcp.service["}, "output": ["itemid", "key_"]})
             if i["key_"] not in keep]
    if stale:
        api("item.delete", stale)   # comprobaciones que ya no están en la lista (se borran con sus disparadores)
    for label, proto, port in checks:
        key = f"net.tcp.service[{proto},{ip},{port}]"
        item(hid, ifid, f"Servicio {label} ({proto}/{port})", key, type=3)
        trigger(hid, f"{name}: servicio {label} caído", f"max(/{name}/{key},#3)=0", SEV["high"],
                f"{label} no responde en {ip}:{port} en 3 comprobaciones seguidas (Tabla 13: servicio caído).")
    return hid, ifid


# ---------- Site A ----------
A = "Site A"
servicios("fw-a1", "10.10.40.2", A, [("GUI OPNsense", "https", 443)], "OPNsense 26.7 (CARP maestro; supervisado por su IP de ADMIN, única con GUI/SSH). Equivale al firewall de borde del Site A.")
servicios("fw-a2", "10.10.40.3", A, [("GUI OPNsense", "https", 443)], "OPNsense 26.7 (CARP respaldo).")
servicios("vip-carp-a", "10.10.20.1", A, [], "Gateway virtual CARP de la VLAN SERVIDORES (lo atiende el FW maestro).")
for n, ip in (("sw-a1", "10.10.10.11"), ("sw-a2", "10.10.10.12")):
    servicios(n, ip, A, [], "Switch de acceso Open vSwitch (camino de energía " + ("A)" if n.endswith("1") else "B)"))
servicios("dc1", "10.10.20.10", A, [("DNS", "tcp", 53), ("Kerberos", "tcp", 88), ("LDAP", "ldap", 389), ("LDAPS", "tcp", 636), ("SMB", "tcp", 445)], "Samba AD DC principal (ad.alcaldia.lab).")
servicios("authelia", "10.10.20.11", A, [("Authelia (MFA)", "http", 9091)], "SSO + TOTP.")
servicios("gate", "10.10.20.13", A, [("horario-gate", "http", 9200)], "Política de horario laboral para la web.")
servicios("portal", "10.10.20.20", A, [("Portal ciudadano", "http", 8000)], "FastAPI.")
servicios("archivo", "10.10.20.21", A, [("Archivo (filebrowser)", "http", 80)], "Archivo documental.")
servicios("portal-db", "10.10.20.22", A, [("PostgreSQL", "tcp", 5432)], "BD del portal (primaria).")
servicios("mailpit", "10.10.20.32", A, [("SMTP", "smtp", 1025), ("Web", "http", 8025)], "Buzón de pruebas: recibe las alertas.")
servicios("ts1", "10.10.20.40", A, [("Escritorios RDP", "tcp", 3389)], "Escritorios XFCE por RDP (xrdp + winbind).")
servicios("lam", "10.10.20.50", A, [("LAM (gestión de identidades)", "http", 80)], "Solo vía WARP.")
servicios("zbx-db", "10.10.20.34", A, [("PostgreSQL Zabbix", "tcp", 5432)], "BD de Zabbix.")
servicios("zbx-web", "10.10.20.33", A, [("Frontend Zabbix", "http", 8080)], "Interfaz web de Zabbix.")
servicios("glpi", "10.10.20.31", A, [("GLPI (mesa de servicio)", "http", 80)], "Mesa de servicio GLPI 11 (mesa.evervc.dev, SSO con el AD).")
servicios("glpi-db", "10.10.20.35", A, [("MariaDB GLPI", "tcp", 3306)], "BD de GLPI (MariaDB 11.4).")
servicios("nginx-dmz", "10.10.30.10", A, [("HTTP", "http", 80), ("HTTPS", "tcp", 443)], "Proxy inverso de la DMZ.")
servicios("cloudflared-a", "10.10.30.11", A, [], "Conector Cloudflare Tunnel del Site A (y WARP).")

# NAS: salud + % ocupado (métricas Prometheus de MinIO)
def nas(name, ip, grp):
    hid, ifid = servicios(name, ip, grp, [("MinIO S3", "http", 9000)], "NAS de respaldo (MinIO con Object Lock).")
    master = item(hid, None, "Métricas MinIO (texto)", "minio.metrics", type=19, value_type=4, delay="5m",
                  url=f"http://{ip}:9000/minio/v2/metrics/cluster", history="1h", trends="0")
    for k, metric in (("free", "minio_cluster_capacity_usable_free_bytes"), ("total", "minio_cluster_capacity_usable_total_bytes")):
        item(hid, None, f"Capacidad {k} (bytes)", f"nas.{k}", type=18, master_itemid=master, value_type=0, delay="0", units="B",
             preprocessing=[{"type": 22, "params": f"{metric}\nvalue\n", "error_handler": 0, "error_handler_params": ""}])
    item(hid, None, "NAS: espacio ocupado", "nas.usado", type=15, value_type=0, delay="5m", units="%",
         params="100*(1-last(//nas.free)/last(//nas.total))")
    trigger(hid, f"{name}: ocupación > 80 %", f"last(/{name}/nas.usado)>80", SEV["warning"], "Tabla 13: NAS por encima del 80 %.")
    trigger(hid, f"{name}: ocupación > 90 %", f"last(/{name}/nas.usado)>90", SEV["high"], "Tabla 13: NAS casi lleno.")
nas("nas-a", "10.10.60.10", A)

# ---------- Site B ----------
B = "Site B"
servicios("fw-b", "10.20.40.1", B, [("GUI OPNsense", "https", 443)], "OPNsense del Site B (Tier I, DR en caliente).")
for n, ip in (("sw-b1", "10.20.10.11"), ("sw-b2", "10.20.10.12")):
    servicios(n, ip, B, [], "Switch Open vSwitch del Site B.")
servicios("dc2", "10.20.20.10", B, [("DNS", "tcp", 53), ("Kerberos", "tcp", 88), ("LDAP", "ldap", 389)], "Samba AD DC secundario.")
hid, _ = servicios("portal-db-b", "10.20.20.22", B, [("PostgreSQL", "tcp", 5432)], "Réplica de la BD del portal (pg_dump cada hora).")
key = 'db.odbc.select[replica_edad,,"Driver=/usr/lib/psqlodbcw.so;Server=10.20.20.22;Port=5432;Database=portal"]'
item(hid, None, "Antigüedad de la réplica (s)", key, type=11, delay="5m", units="s", username="portal", password=PORTAL_DB_PASS,
     params="SELECT extract(epoch from now() - pg_read_file('replica_ok')::timestamptz)::int")
TRIG["replica"] = trigger(hid, "portal-db-b: réplica atrasada (> RPO 1 h)", f"last(/portal-db-b/{key})>3900", SEV["high"],
                          "La última copia correcta desde portal-db tiene más de 65 min: se incumple el RPO de 1 h (Fase 4).")
trigger(hid, "portal-db-b: no se puede comprobar la réplica", f"nodata(/portal-db-b/{key},15m)=1", SEV["average"])
servicios("nginx-dmz-b", "10.20.30.10", B, [("HTTP", "http", 80)], "Proxy DMZ del Site B (espera).")
servicios("cloudflared-b", "10.20.30.11", B, [], "Conector Cloudflare del Site B (DR).")
nas("nas-b", "10.20.60.10", B)

# ---------- Enlaces WAN y túneles A<->B ----------
W = "Enlaces WAN"
servicios("isp1-gw-a", "203.0.113.1", W, [], "Gateway de ISP1 visto desde el Site A (WAN1).")
servicios("isp2-gw-a", "198.51.100.1", W, [], "Gateway de ISP2 visto desde el Site A (WAN2).")
servicios("tunel-ab-isp1", "172.16.0.2", W, [], "Extremo B del túnel IPsec A<->B por ISP1 (VTI ipsec1).")
servicios("tunel-ab-isp2", "172.16.0.6", W, [], "Extremo B del túnel IPsec A<->B por ISP2 (VTI ipsec2).")


def icmp_trigger(name):
    t = api("trigger.get", {"hostids": HOSTS[name], "search": {"description": "Unavailable by ICMP"}, "output": ["triggerid"]})
    return t[0]["triggerid"] if t else None


# ---------- Sedes (SNMP) ----------
def oid_extend(name):   # NET-SNMP-EXTEND-MIB::nsExtendOutput1Line."name"
    return ".1.3.6.1.4.1.8072.1.3.2.3.1.1." + ".".join([str(len(name))] + [str(ord(c)) for c in name])


for N in (1, 2, 3):
    n = f"kit-sede-{N:02d}"
    hid, ifid = servicios(n, f"10.100.{N}.1", "Sedes", [], f"Kit de la sede {N} (strongSwan + FRR) tras CGNAT.", snmp=True)
    # Túneles hacia el Site A: se comprueban DESDE el centro de datos (ping al extremo del kit dentro del VTI),
    # así la alerta salta aunque la sede quede aislada. El túnel al Site B, por SNMP del propio kit.
    for t, label, ip in (("tunel-a-wan1", "Site A por WAN1", f"172.16.{N}.2"), ("tunel-a-wan2", "Site A por WAN2", f"172.16.{N}.6")):
        key = f"icmpping[{ip},3,200,,1000]"
        item(hid, ifid, f"Túnel {label} (ping {ip})", key, type=3, delay="20s")
        TRIG[f"{N}-{t}"] = trigger(hid, f"Sede {N}: túnel hacia {label} caído", f"max(/{n}/{key},#3)=0", SEV["average"],
                                   "Tabla 13: túnel caído. OSPF conmuta al siguiente túnel (WAN1 -> WAN2 -> Site B).")
        item(hid, ifid, f"Túnel {label} (SA IPsec en el kit)", f"acc.{t}", type=20, snmp_oid=oid_extend(t), delay="30s")
    item(hid, ifid, "Túnel Site B (SA IPsec en el kit)", "acc.tunel-b", type=20, snmp_oid=oid_extend("tunel-b"), delay="30s")
    TRIG[f"{N}-tunel-b"] = trigger(hid, f"Sede {N}: túnel hacia Site B caído", f"max(/{n}/acc.tunel-b,#2)=0", SEV["average"],
                                   "Tabla 13: túnel de respaldo al Site B caído (la sede pierde la ruta de DR).")
    item(hid, ifid, "Vecinos OSPF en Full", "acc.ospf-full", type=20, snmp_oid=oid_extend("ospf-full"), delay="30s")
    trigger(hid, f"Sede {N}: menos de 3 vecinos OSPF", f"last(/{n}/acc.ospf-full)<3 and last(/{n}/acc.ospf-full)>0", SEV["warning"],
            "Algún túnel no tiene adyacencia OSPF (redundancia reducida).")
    key = f"icmpping[10.100.{N}.1,3,200,,1000]"
    item(hid, ifid, "Sede alcanzable desde el centro de datos", key, type=3, delay="20s")
    trigger(hid, f"Sede {N}: AISLADA (sin ningún túnel)", f"max(/{n}/{key},#3)=0", SEV["disaster"],
            "La sede no es alcanzable por ningún túnel (WAN de la sede caída o los 3 túneles abajo).")

# disparadores de versiones anteriores del script
for t in api("trigger.get", {"hostids": [HOSTS[f"kit-sede-{N:02d}"] for N in (1, 2, 3)], "output": ["triggerid"],
                             "search": {"description": "sin ningún túnel activo"}}):
    api("trigger.delete", [t["triggerid"]])

# ---------- Respaldos (F9): antigüedad del último snapshot restic de cada equipo ----------
# Comprobación externa en zbx-server (restic con la cuenta de SOLO LECTURA, sin bloquear el repositorio);
# el JSON se convierte en segundos con JavaScript. Diario a las 02:00 -> alerta si pasan más de 26 h.
JS_EDAD = ("var s = JSON.parse(value); if (!s.length) { return 999999999; }"
           " var t = s[0].time.replace(/\\.\\d+/, ''); return Math.floor(Date.now() / 1000 - Date.parse(t) / 1000);")
# RPO (Fase 2): archivo y mesa de servicio 4 h -> respaldo cada 4 h, alerta a las 5 h; el resto diario, alerta a las 26 h
for eq, lim in (("ts1", 26), ("archivo", 5), ("portal-db", 26), ("dc1", 26), ("glpi-db", 5), ("glpi", 5), ("zbx-db", 26)):
    hid = HOSTS[eq]
    key = f'restic-ultimo.sh["{eq}"]'
    item(hid, None, "Respaldo: antigüedad del último (restic)", key, type=10, delay="15m", units="s", timeout="60s",
         preprocessing=[{"type": 21, "params": JS_EDAD, "error_handler": 0, "error_handler_params": ""}])
    desc = f"{eq}: sin respaldo en más de {lim} h"
    for t in api("trigger.get", {"hostids": hid, "search": {"description": "sin respaldo en más de"}, "output": ["triggerid", "description"]}):
        if t["description"] != desc: api("trigger.delete", [t["triggerid"]])   # umbral anterior
    trigger(hid, desc, f"last(/{eq}/{key})>{lim * 3600}", SEV["high"],
            ("Respaldo cada 4 h (RPO 4 h de la Fase 2)" if lim < 24 else "El respaldo diario (02:00)") +
            " no se ha completado. Ver /var/log/respaldo.log en el equipo.")
    trigger(hid, f"{eq}: no se puede comprobar el respaldo", f"nodata(/{eq}/{key},2h)=1", SEV["average"],
            "Zabbix no puede leer el repositorio restic en nas-a.")

# ---------- IDS/IPS (Suricata en las WAN de los OPNsense; vigía acc-ids-vigia.py cada minuto, trapper) ----------
for fw in ("fw-a1", "fw-a2", "fw-b"):
    hid = HOSTS[fw]
    item(hid, None, "IDS: alertas en el último minuto", "ids.alertas", type=2, delay="0", value_type=3)
    item(hid, None, "IDS: IP bloqueadas por respuesta activa", "ids.bloqueadas", type=2, delay="0", value_type=3)
    item(hid, None, "IDS: última alerta", "ids.ultima", type=2, delay="0", value_type=4)
    trigger(hid, f"{fw}: IDS detectó un ataque desde Internet (IP bloqueada 1 h)",
            f"max(/{fw}/ids.alertas,10m)>0 and length(last(/{fw}/ids.ultima))>0", SEV["high"],
            "Suricata (ET Open) alertó en una WAN; el vigía bloqueó la IP de origen 1 h (tabla ACC_IDS_BLOQUEO). "
            "Ver la alerta en Servicios > Detección de intrusiones del firewall.")
    t = api("trigger.get", {"hostids": hid, "filter": {"description": f"{fw}: IDS detectó un ataque desde Internet (IP bloqueada 1 h)"}, "output": ["triggerid"]})
    if t: api("trigger.update", {"triggerid": t[0]["triggerid"], "opdata": "{ITEM.LASTVALUE2}"})
    trigger(hid, f"{fw}: el vigía del IDS no informa", f"nodata(/{fw}/ids.alertas,10m)=1", SEV["warning"],
            "El cron 'acc ids-vigia' del firewall no envía datos (¿Suricata o el cron detenidos?).")

# ---------- Tareas programadas (scripts/tareas.sh en el host, systemd --user cada hora) ----------
# Trapper: el script envía 1 (OK) o 0 (fallo) con zabbix_sender. Sin dato en el plazo -> la tarea no se ejecuta.
hid, _ = host("tareas-programadas", None, "Site A",
              desc="Tareas automáticas: respaldo de configuraciones de red (diario) y cinta LTO (semanal). Registro: ~/.local/state/acc/tareas.log")
HOSTS["tareas-programadas"] = hid
for tarea, nombre, plazo in (("configs", "Respaldo de configuraciones de red", "26h"), ("cinta", "Grabación de cinta (nodo tape)", "8d")):
    key = f"acc.tarea[{tarea}]"
    item(hid, None, f"{nombre}: resultado (1 = OK)", key, type=2, delay="0", value_type=3)
    trigger(hid, f"{nombre}: FALLÓ", f"last(/tareas-programadas/{key})=0", SEV["high"],
            "Ver ~/.local/state/acc/tareas.log en el host. Repetir: scripts/tareas.sh ahora " + tarea)
    trigger(hid, f"{nombre}: no se ejecuta (sin resultado en {plazo})", f"nodata(/tareas-programadas/{key},{plazo})=1",
            SEV["average"], "¿Temporizador instalado? systemctl --user list-timers acc-tareas.timer")

# ---------- Servicio público (ruta Internet -> Cloudflare -> túnel -> DMZ) ----------
hid, _ = host("internet-evervc", None, "Internet", desc="Servicios publicados en Internet vía Cloudflare Tunnel.")
HOSTS["internet-evervc"] = hid
for svc, url in (("Portal público", "https://portal.evervc.dev/"),):
    if not api("httptest.get", {"hostids": hid, "filter": {"name": svc}}):
        api("httptest.create", {"hostid": hid, "name": svc, "delay": "1m", "retries": 2,
                                "steps": [{"name": "inicio", "no": 1, "url": url, "status_codes": "200", "timeout": "15s"}]})
    TRIG["publico"] = trigger(hid, f"{svc} inaccesible desde Internet", f"last(/internet-evervc/web.test.fail[{svc}])>0",
                              SEV["high"], "Falla la ruta completa: DNS de Cloudflare, túnel, nginx-dmz o el servicio.")

# ---------- Alertas por correo (mailpit) ----------
mt = api("mediatype.get", {"filter": {"name": "Email"}, "output": ["mediatypeid"]})[0]["mediatypeid"]
CUERPO = ("Equipo: {HOST.NAME} ({HOST.IP})\nProblema: {EVENT.NAME}\nSeveridad: {EVENT.SEVERITY}\nInicio: {EVENT.DATE} {EVENT.TIME}\n"
          "Grupo: {TRIGGER.HOSTGROUP.NAME}\n\nDetalle: {TRIGGER.DESCRIPTION}\n\nID de evento: {EVENT.ID}\n-- Monitoreo Alcaldía Digital (Zabbix)")
api("mediatype.update", {"mediatypeid": mt, "status": 0, "smtp_server": "10.10.20.32", "smtp_port": 1025,
                         "smtp_helo": "alcaldia.lab", "smtp_email": "zabbix@alcaldia.lab", "message_templates": [
    {"eventsource": 0, "recovery": 0, "subject": "[{EVENT.SEVERITY}] {HOST.NAME}: {EVENT.NAME}", "message": CUERPO},
    {"eventsource": 0, "recovery": 1, "subject": "[RESUELTO] {HOST.NAME}: {EVENT.NAME} (duró {EVENT.DURATION})",
     "message": "Resuelto: {EVENT.RECOVERY.DATE} {EVENT.RECOVERY.TIME}\n" + CUERPO},
    {"eventsource": 0, "recovery": 2, "subject": "[ACTUALIZADO] {HOST.NAME}: {EVENT.NAME}",
     "message": "{USER.FULLNAME} actualizó el problema: {EVENT.UPDATE.MESSAGE}\n" + CUERPO}]})
# ---------- Tickets en GLPI (mesa.evervc.dev): webhook propio por la API REST de GLPI ----------
# Problema -> ticket de incidente (el n.º queda como etiqueta del evento __zbx_glpi_ticket); actualización -> seguimiento;
# resuelto -> solución (el ticket pasa a «Resuelto»). Contraseña del usuario GLPI 'zabbix' en macro secreta.
GLPI_JS = r"""
var p = JSON.parse(value);
function req(method, path, body, headers) {
  var r = new HttpRequest(), resp, url = p.glpi_url + path;
  r.addHeader('Content-Type: application/json');
  for (var i = 0; i < headers.length; i++) { r.addHeader(headers[i]); }
  if (method === 'GET') { resp = r.get(url); } else { resp = r.post(url, body ? JSON.stringify(body) : ''); }
  var st = r.getStatus();
  if (st < 200 || st >= 300) { throw 'GLPI ' + method + ' ' + path + ': HTTP ' + st + ' ' + resp; }
  return resp ? JSON.parse(resp) : null;
}
var html = function (t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, '<br>'); };
var tok = req('GET', '/initSession', null, ['Authorization: Basic ' + btoa(p.glpi_user + ':' + p.glpi_pass)]).session_token;
var H = ['Session-Token: ' + tok], out = {}, tid = p.ticket_id;
if (!/^[0-9]+$/.test(tid || '')) { tid = ''; }   // sin ticket: la macro llega como *UNKNOWN* o sin resolver
try {
  if (p.event_value === '1' && p.event_update_status === '0' && !tid) {
    var u = {'0': 1, '1': 2, '2': 2, '3': 3, '4': 4, '5': 5}[p.severity] || 3;
    var yo = req('GET', '/getFullSession', null, H).session.glpiID;   // el ticket se asigna al propio usuario zabbix: así puede resolverlo
    var t = req('POST', '/Ticket', {input: {name: p.subject, content: html(p.message), type: 1, urgency: u, impact: u,
                                             itilcategories_id: parseInt(p.category_id, 10), _users_id_assign: yo}}, H);
    out.tags = {'__zbx_glpi_ticket': String(t.id)};
    Zabbix.log(4, '[GLPI] ticket ' + t.id + ' para el evento ' + p.event_id);
  } else if (tid) {
    var it = {itemtype: 'Ticket', items_id: parseInt(tid, 10)};
    if (p.event_value === '0') { it.content = 'Resuelto automáticamente por el monitoreo (Zabbix).<br>' + html(p.message); req('POST', '/ITILSolution', {input: it}, H); }
    else { it.content = html(p.message); req('POST', '/ITILFollowup', {input: it}, H); }
  }
} finally { try { req('GET', '/killSession', null, H); } catch (e) {} }
return JSON.stringify(out);
"""
m = api("usermacro.get", {"globalmacro": True, "filter": {"macro": "{$GLPI_ZABBIX_PASS}"}})
if m: api("usermacro.updateglobal", {"globalmacroid": m[0]["globalmacroid"], "value": os.environ["GLPI_ZABBIX_PASS"], "type": 1})
else: api("usermacro.createglobal", {"macro": "{$GLPI_ZABBIX_PASS}", "value": os.environ["GLPI_ZABBIX_PASS"], "type": 1,
                                     "description": "Usuario 'zabbix' de GLPI (API, tickets)"})
GP = {"glpi_url": "http://10.10.20.31/apirest.php", "glpi_user": "zabbix", "glpi_pass": "{$GLPI_ZABBIX_PASS}",
      "category_id": "1", "event_id": "{EVENT.ID}", "event_value": "{EVENT.VALUE}", "event_update_status": "{EVENT.UPDATE.STATUS}",
      "severity": "{EVENT.NSEVERITY}", "ticket_id": "{EVENT.TAGS.__zbx_glpi_ticket}", "subject": "{ALERT.SUBJECT}", "message": "{ALERT.MESSAGE}"}
MT_GLPI = {"name": "GLPI (mesa de servicio)", "type": 4, "status": 0, "script": GLPI_JS, "timeout": "30s",
           "process_tags": 1, "show_event_menu": 1, "event_menu_name": "Ticket GLPI #{EVENT.TAGS.__zbx_glpi_ticket}",
           "event_menu_url": "https://mesa.evervc.dev/front/ticket.form.php?id={EVENT.TAGS.__zbx_glpi_ticket}",
           "description": "Abre, actualiza y resuelve tickets en GLPI (mesa.evervc.dev). Gestionado por zbx-setup.py",
           "parameters": [{"name": k, "value": v} for k, v in GP.items()],
           "message_templates": [
               {"eventsource": 0, "recovery": 0, "subject": "[Zabbix] {HOST.NAME}: {EVENT.NAME}", "message": CUERPO},
               {"eventsource": 0, "recovery": 1, "subject": "[RESUELTO] {HOST.NAME}: {EVENT.NAME}",
                "message": "Resuelto: {EVENT.RECOVERY.DATE} {EVENT.RECOVERY.TIME} (duró {EVENT.DURATION})\n" + CUERPO},
               {"eventsource": 0, "recovery": 2, "subject": "[ACTUALIZADO] {HOST.NAME}: {EVENT.NAME}",
                "message": "{USER.FULLNAME} actualizó el problema: {EVENT.UPDATE.MESSAGE}\n" + CUERPO}]}
g = api("mediatype.get", {"filter": {"name": MT_GLPI["name"]}, "output": ["mediatypeid"]})
mt_glpi = (api("mediatype.update", {"mediatypeid": g[0]["mediatypeid"], **MT_GLPI}) if g else api("mediatype.create", MT_GLPI))["mediatypeids"][0]

uid = api("user.get", {"filter": {"username": "Admin"}, "output": ["userid"]})[0]["userid"]
api("user.update", {"userid": uid, "medias": [
    {"mediatypeid": mt, "sendto": ["ti@alcaldia.lab"], "active": 0, "severity": 60, "period": "1-7,00:00-24:00"},   # 60 = advertencia y superiores
    {"mediatypeid": mt_glpi, "sendto": ["mesa"], "active": 0, "severity": 60, "period": "1-7,00:00-24:00"}]})       # 60 = advertencia y superiores -> ticket (Tabla 13: también P3)
for a in api("action.get", {"filter": {"name": "Report problems to Zabbix administrators"}, "output": ["actionid"]}):
    api("action.update", {"actionid": a["actionid"], "status": 0})
# Host "Zabbix server": se conserva la salud interna del servidor; sin agente en el contenedor -> fuera la plantilla de agente
for h in api("host.get", {"filter": {"host": ["Zabbix server"]}, "output": ["hostid"], "selectParentTemplates": ["templateid", "host"]}):
    quitar = [{"templateid": t["templateid"]} for t in h["parentTemplates"] if "agent" in t["host"]]
    api("host.update", {"hostid": h["hostid"], "status": 0, "templates_clear": quitar,
                        "groups": [{"groupid": G["Site A"]}], "name": "zbx-server (salud de Zabbix)"})

# ---------- Mapa de red ----------
imgs = {i["name"]: i["imageid"] for i in api("image.get", {"filter": {"imagetype": 1}, "output": ["imageid", "name"]})}
def icon(*names):
    for n in names:
        if n in imgs: return imgs[n]
    return next(v for k, v in imgs.items() if "Server" in k)
IC = {"fw": icon("Firewall_(64)", "Router_(64)"), "sw": icon("Switch_(64)"), "srv": icon("Server_(64)"),
      "rt": icon("Router_(64)", "Router_symbol_(64)"), "cloud": icon("Cloud_(64)", "Cloud_(48)"), "nas": icon("Disk_array_2D_(64)", "Server_(64)")}

POS = {  # nombre: (x, y, icono)
    "internet-evervc": (700, 40, "cloud"),
    "isp1-gw-a": (420, 150, "rt"), "isp2-gw-a": (560, 150, "rt"),
    "kit-sede-01": (760, 150, "rt"), "kit-sede-02": (880, 150, "rt"), "kit-sede-03": (1000, 150, "rt"),
    "tunel-ab-isp1": (1150, 230, "rt"), "tunel-ab-isp2": (1150, 300, "rt"),
    "fw-a1": (420, 280, "fw"), "fw-a2": (560, 280, "fw"), "vip-carp-a": (490, 360, "fw"),
    "sw-a1": (420, 440, "sw"), "sw-a2": (560, 440, "sw"),
    "nginx-dmz": (60, 280, "srv"), "cloudflared-a": (60, 380, "srv"),
    "dc1": (60, 560, "srv"), "authelia": (150, 560, "srv"), "gate": (240, 560, "srv"), "portal": (330, 560, "srv"),
    "archivo": (420, 560, "srv"), "portal-db": (510, 560, "srv"), "ts1": (600, 560, "srv"), "lam": (690, 560, "srv"),
    "mailpit": (60, 680, "srv"), "zbx-db": (150, 680, "srv"), "zbx-web": (240, 680, "srv"), "nas-a": (420, 680, "nas"),
    "fw-b": (1150, 420, "fw"), "sw-b1": (1080, 520, "sw"), "sw-b2": (1220, 520, "sw"),
    "dc2": (1000, 640, "srv"), "portal-db-b": (1090, 640, "srv"), "nginx-dmz-b": (1180, 640, "srv"),
    "cloudflared-b": (1270, 640, "srv"), "nas-b": (1135, 740, "nas"),
}
els, sid = [], {}
for i, (n, (x, y, ic)) in enumerate(POS.items(), 1):
    sid[n] = str(i)
    els.append({"selementid": str(i), "elementtype": 0, "elements": [{"hostid": HOSTS[n]}], "iconid_off": IC[ic],
                "label": "{HOST.NAME}\n{HOST.CONN}" if n != "internet-evervc" else "Internet / Cloudflare\nportal.evervc.dev",
                "x": x, "y": y})

def link(a, b, trig_keys=(), label=""):
    l = {"selementid1": sid[a], "selementid2": sid[b], "color": "2E7D32", "label": label}
    lt = [{"triggerid": TRIG[k], "drawtype": 2, "color": "DD0000"} for k in trig_keys if TRIG.get(k)]
    for h in (a, b):
        t = icmp_trigger(h) if h in HOSTS else None
        if t and h.startswith(("tunel", "isp", "kit")): lt.append({"triggerid": t, "drawtype": 2, "color": "DD0000"})
    if lt: l["linktriggers"] = lt
    return l

links = [link("internet-evervc", "cloudflared-a", ["publico"], "Cloudflare Tunnel"),
         link("cloudflared-a", "nginx-dmz"), link("nginx-dmz", "fw-a1"),
         link("fw-a1", "isp1-gw-a", label="WAN1"), link("fw-a2", "isp2-gw-a", label="WAN2"),
         link("fw-a1", "fw-a2", label="CARP/pfsync"), link("fw-a1", "vip-carp-a"), link("fw-a2", "vip-carp-a"),
         link("vip-carp-a", "sw-a1"), link("vip-carp-a", "sw-a2"),
         link("fw-a1", "tunel-ab-isp1", label="IPsec ISP1"), link("fw-a2", "tunel-ab-isp2", label="IPsec ISP2"),
         link("tunel-ab-isp1", "fw-b"), link("tunel-ab-isp2", "fw-b"),
         link("fw-b", "sw-b1"), link("fw-b", "sw-b2"),
         link("portal-db", "portal-db-b", ["replica"], "réplica 1 h"), link("nas-a", "nas-b", label="replicación WORM")]
for N in (1, 2, 3):
    k = f"kit-sede-{N:02d}"
    links += [link(k, "fw-a1", [f"{N}-tunel-a-wan1"], "WAN1"), link(k, "fw-a2", [f"{N}-tunel-a-wan2"], "WAN2"),
              link(k, "fw-b", [f"{N}-tunel-b"], "B")]
for s in ("dc1", "authelia", "gate", "portal", "archivo", "portal-db", "ts1", "lam", "mailpit", "zbx-db", "zbx-web", "nas-a"):
    links.append(link(s, "sw-a1" if POS[s][0] < 500 else "sw-a2"))
for s in ("dc2", "portal-db-b", "nginx-dmz-b", "cloudflared-b", "nas-b"):
    links.append(link(s, "sw-b1" if POS[s][0] < 1135 else "sw-b2"))

shapes = [
    {"type": 0, "x": 20, "y": 230, "width": 760, "height": 530, "text": "SITE A · Tier II (principal)", "font_size": 11,
     "text_valign": 1, "text_halign": 1, "border_color": "1565C0", "background_color": "EEF4FC", "border_width": 2},
    {"type": 0, "x": 960, "y": 380, "width": 380, "height": 400, "text": "SITE B · Tier I (DR en caliente)", "font_size": 11,
     "text_valign": 1, "text_halign": 1, "border_color": "6A1B9A", "background_color": "F6EEFA", "border_width": 2},
    {"type": 0, "x": 720, "y": 110, "width": 360, "height": 100, "text": "SEDES (hub-and-spoke)", "font_size": 11,
     "text_valign": 1, "text_halign": 1, "border_color": "B7791F", "background_color": "FFF8E1", "border_width": 2},
]
for m in api("map.get", {"filter": {"name": "Alcaldía Digital"}, "output": ["sysmapid"]}):
    api("map.delete", [m["sysmapid"]])
api("map.create", {"name": "Alcaldía Digital", "width": 1400, "height": 800, "label_type": 0, "highlight": 1,
                      "expandproblem": 1, "markelements": 1, "show_unack": 0, "selements": els, "links": links, "shapes": shapes})

print(f"Zabbix configurado: {len(HOSTS)} hosts, {len(TRIG)} disparadores clave de enlaces/réplica, mapa 'Alcaldía Digital', "
      "alertas -> ti@alcaldia.lab (mailpit)")
