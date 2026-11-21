#!/usr/bin/env python3
"""horario-gate: decide si un usuario del AD puede usar los servicios web AHORA.
GET /authz  (nginx auth_request) -> consulta a Authelia (sesión + MFA); si es válida, aplica el horario.
            Devuelve 200 (+cabeceras Remote-*), 401/302 de Authelia tal cual, o 403 si está fuera de horario.
GET /check  (cabecera Remote-User puesta por Authelia)  -> 200 permitido | 403 fuera de horario
GET /denegado?u=<usuario>                             -> página HTML con el motivo
Regla (config/politicas/horario.conf -> /etc/acc/horario.conf): GRUPO_RESTRINGIDO solo en DIAS/DESDE-HASTA; GRUPO_EXENTO siempre.
Configuración por variables de entorno: LDAP_URL, LDAP_BIND_DN, LDAP_BIND_PW (leída de /etc/acc/gate.env), LDAP_BASE."""
import os, ssl, html, datetime, http.server, urllib.parse, urllib.request, urllib.error, ldap3

def load_env(path="/etc/acc/gate.env"):
    if os.path.exists(path):
        for line in open(path):
            if "=" in line and not line.startswith("#"):
                k, v = line.rstrip("\n").split("=", 1); os.environ.setdefault(k, v)
load_env()
URLS = os.environ.get("LDAP_URL", "ldaps://10.10.20.10,ldaps://10.20.20.10").split(",")
BASE = os.environ.get("LDAP_BASE", "DC=ad,DC=alcaldia,DC=lab")
AUTHELIA = os.environ.get("AUTHELIA_URL", "http://10.10.20.11:9091")
TZ_LOCAL = datetime.timezone(datetime.timedelta(hours=-6))   # El Salvador, sin horario de verano (solo para la página)

def politica():
    p = {"GRUPO_RESTRINGIDO": "funcionarios", "GRUPO_EXENTO": "acceso-24h", "DIAS": "1,2,3,4,5",
         "DESDE": "08:00", "HASTA": "16:00", "TZ_OFFSET": "-6"}
    if os.path.exists("/etc/acc/horario.conf"):
        for line in open("/etc/acc/horario.conf"):
            line = line.split("#")[0].strip()
            if "=" in line: k, v = line.split("=", 1); p[k.strip()] = v.strip()
    return p

def groups_of(user):
    pool = ldap3.ServerPool([ldap3.Server(u, connect_timeout=3, get_info=ldap3.NONE, tls=ldap3.Tls(validate=ssl.CERT_NONE)) for u in URLS], ldap3.FIRST, active=1)
    c = ldap3.Connection(pool, os.environ["LDAP_BIND_DN"], os.environ["LDAP_BIND_PW"], auto_bind=True)
    c.search(BASE, f"(sAMAccountName={ldap3.utils.conv.escape_filter_chars(user)})", attributes=["memberOf"])
    if not c.entries: return []
    e = c.entries[0]
    return [g.split(",")[0][3:].lower() for g in e.memberOf.values] if e.memberOf else []

def dentro_horario(p):
    tz = datetime.timezone(datetime.timedelta(hours=int(p["TZ_OFFSET"])))
    now = datetime.datetime.now(tz)
    dias = {int(d) for d in p["DIAS"].split(",") if d.strip()}
    hm = now.strftime("%H:%M")
    return now.isoweekday() in dias and p["DESDE"] <= hm < p["HASTA"]

def allowed(user):
    p = politica(); groups = groups_of(user)
    if p["GRUPO_EXENTO"].lower() in groups: return True, p["GRUPO_EXENTO"]
    if p["GRUPO_RESTRINGIDO"].lower() not in groups: return True, "sin restricción de horario"
    return dentro_horario(p), f"{p['GRUPO_RESTRINGIDO']} {p['DESDE']}-{p['HASTA']} días {p['DIAS']}"

PAGE = """<!doctype html><html lang="es"><meta charset="utf-8"><title>Fuera del horario laboral</title>
<body style="font-family:sans-serif;max-width:640px;margin:4rem auto;line-height:1.5">
<h1>Acceso fuera del horario laboral</h1>
<p>La cuenta <b>{u}</b> solo puede usar los servicios del centro de datos <b>de lunes a viernes, de 8:00 a 16:00</b> (hora de El Salvador).</p>
<p>Hora actual: <b>{t}</b>.</p>
<p>Si necesita acceso fuera de este horario, contacte a la Mesa de Servicio (GLPI) para una autorización temporal.</p>
<p style="color:#666">Alcaldía Digital · control de horario basado en el directorio (logonHours)</p></body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        if p.path == "/authz":
            fwd = {k: v for k, v in self.headers.items() if k.lower() in (
                "cookie", "authorization", "proxy-authorization", "x-original-url", "x-original-method",
                "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host", "x-forwarded-uri", "x-forwarded-method", "user-agent")}
            req = urllib.request.Request(AUTHELIA + "/api/authz/auth-request", headers=fwd)
            class NoRedirect(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *a, **k): return None
            try:
                r = urllib.request.build_opener(NoRedirect).open(req, timeout=5); code, hdrs = r.status, r.headers
            except urllib.error.HTTPError as e:
                code, hdrs = e.code, e.headers
            except Exception as ex:
                print(f"authelia inaccesible: {ex}", flush=True); self.send_response(500); self.end_headers(); return
            if code != 200:                       # sin sesión / sin MFA: lo decide Authelia (redirección al login)
                self.send_response(code)
                for h in ("Location", "Set-Cookie"):
                    for v in hdrs.get_all(h) or []: self.send_header(h, v)
                self.end_headers(); return
            u = hdrs.get("Remote-User", "")
            try: ok, why = allowed(u)
            except Exception as ex: ok, why = True, f"fallo LDAP, se permite: {ex}"
            print(f"{datetime.datetime.now().isoformat()} authz user={u} ok={ok} motivo={why}", flush=True)
            self.send_response(200 if ok else 403)
            for h in ("Remote-User", "Remote-Groups", "Remote-Name", "Remote-Email"):
                if hdrs.get(h): self.send_header(h, hdrs.get(h))
            self.send_header("X-Gate-User", u); self.end_headers(); return
        if p.path == "/check":
            u = self.headers.get("Remote-User", "")
            try: ok, why = allowed(u) if u else (False, "sin usuario")
            except Exception as ex: ok, why = True, f"fallo LDAP, se permite: {ex}"   # no bloquear por error del gate
            print(f"{datetime.datetime.now().isoformat()} user={u} ok={ok} motivo={why}", flush=True)
            self.send_response(200 if ok else 403); self.end_headers(); return
        if p.path == "/denegado":
            u = html.escape(urllib.parse.parse_qs(p.query).get("u", ["(desconocido)"])[0])
            body = PAGE.format(u=u, t=datetime.datetime.now(TZ_LOCAL).strftime("%A %d/%m/%Y %H:%M")).encode()
            self.send_response(403); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers(); self.wfile.write(body); return
        self.send_response(404); self.end_headers()

http.server.ThreadingHTTPServer(("0.0.0.0", 9200), H).serve_forever()
