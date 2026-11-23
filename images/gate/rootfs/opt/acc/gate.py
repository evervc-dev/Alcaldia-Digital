#!/usr/bin/env python3
"""gate: ¿puede este usuario del AD usar los servicios AHORA? + administración de horarios y accesos de emergencia.
GET /authz     nginx auth_request: Authelia (sesión + MFA) y después la política (acc_politica.py).
GET /denegado  página con el motivo.
/accesos       administración (lam.evervc.dev/accesos, solo WARP). Identidad: gate pregunta a Authelia con la cookie (no se fía de
               cabeceras); rol-admin edita horarios y excepciones de hasta 72 h; rol-ti solo excepciones de hasta 4 h para rol-soporte.
Falla CERRADO: sin AD usa la última lectura buena (15 min); pasado eso deniega. Rescate local: /etc/acc/rescate.json (scripts/acceso-rescate.sh)."""
import datetime, html, http.server, json, os, re, smtplib, ssl, sys, threading, time, urllib.error, urllib.parse, urllib.request, uuid, base64
from email.message import EmailMessage
import ldap3
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from acc_politica import POR_DEFECTO, evaluar, texto
def load_env(path="/etc/acc/gate.env"):
    if os.path.exists(path):
        for l in open(path):
            if "=" in l and not l.startswith("#"):
                k, v = l.rstrip("\n").split("=", 1); os.environ.setdefault(k, v)
load_env(); E = os.environ.get
URLS = E("LDAP_URL", "ldaps://10.10.20.10,ldaps://10.20.20.10").split(","); BASE = E("LDAP_BASE", "DC=ad,DC=alcaldia,DC=lab")
OU = "OU=Politica-Acceso," + BASE; AUTHELIA = E("AUTHELIA_URL", "http://10.10.20.11:9091"); ORIGEN = "https://lam.evervc.dev"
TZ = datetime.timezone(datetime.timedelta(hours=-6)); MAX_H = {"rol-admin": 72, "rol-ti": 4}; CACHE = 900
_caido = {"t": 0.0, "bueno": ""}
def ldap(dn, pw):   # un intento por DC (2 s); si fallan todos, 20 s sin reintentar: con el AD caído cada petición tardaba > 20 s
    if time.time() - _caido["t"] < 20: raise RuntimeError("AD no disponible")
    for u in sorted(URLS, key=lambda x: x != _caido["bueno"]):   # primero el último DC que respondió
        try:
            c = ldap3.Connection(ldap3.Server(u, connect_timeout=2, get_info=ldap3.NONE, tls=ldap3.Tls(validate=ssl.CERT_NONE)), dn, pw, auto_bind=True, receive_timeout=4)
            _caido["bueno"] = u; return c
        except ldap3.core.exceptions.LDAPBindError: raise
        except Exception: continue
    _caido["t"] = time.time(); raise RuntimeError("AD no disponible")
lectura = lambda: ldap(E("LDAP_BIND_DN"), E("LDAP_BIND_PW")); escritura = lambda: ldap(E("POLITICA_DN"), E("POLITICA_PW"))
_g, _p, lock = {}, {}, threading.Lock()
def grupos_de(u):
    try:
        c = lectura(); c.search(BASE, f"(&(objectClass=user)(sAMAccountName={ldap3.utils.conv.escape_filter_chars(u)}))", attributes=["memberOf"])
        g = [x.split(",")[0][3:].lower() for x in (c.entries[0].memberOf.values if c.entries and c.entries[0].memberOf else [])]
        _g[u] = (time.time(), g); return g
    except Exception:
        t, g = _g.get(u, (0, None))
        if g is not None and time.time() - t < CACHE: return g
        raise
def politica(fresco=False):
    """(horario, excepciones); se relee cada 5 s; si el AD falla, la última buena durante CACHE"""
    if not fresco and _p and time.time() - _p["t"] < 5: return _p["h"], _p["x"]
    try:
        c = lectura(); c.search(OU, "(&(objectClass=group)(cn=acc-*))", attributes=["cn", "info"]); h, x = POR_DEFECTO, []
        for e in c.entries:
            try: d = json.loads(e.info.value or "")
            except (ValueError, TypeError): continue
            if e.cn.value == "acc-horario": h = d
            elif e.cn.value.startswith("acc-exc-"): d["id"] = e.cn.value[8:]; x.append(d)
        _p.update(t=time.time(), ok=time.time(), h=h, x=x); return h, x
    except Exception:
        if _p and time.time() - _p["ok"] < CACHE: return _p["h"], _p["x"]
        raise
def guardar(cn, d):
    c = escritura(); dn = f"CN={cn},{OU}"; j = json.dumps(d)          # ASCII: los lectores de shell no decodifican base64
    if len(j) > 1000: raise ValueError("datos demasiado largos")
    if not c.add(dn, "group", {"sAMAccountName": cn, "info": j}) and not c.modify(dn, {"info": [(ldap3.MODIFY_REPLACE, [j])]}): raise RuntimeError(c.result["description"])
    _p.clear()
def borrar(cn):
    c = escritura(); c.delete(f"CN={cn},{OU}"); _p.clear()
    if c.result["description"] not in ("success", "noSuchObject"): raise RuntimeError(c.result["description"])
def rescate(u):
    try: d = json.load(open("/etc/acc/rescate.json")); return u in d.get("usuarios", []) and time.time() < d.get("hasta", 0)
    except (OSError, ValueError): return False
def permitido(u):
    if rescate(u): return True, "rescate local", "excepcion", []
    try: g = grupos_de(u); h, x = politica()
    except Exception as ex: return False, f"no se pudo consultar el directorio ({type(ex).__name__})", "error", []
    ok, m, t = evaluar(u, g, h, x); return ok, m, t, g
def log(m): print(datetime.datetime.now(TZ).isoformat(timespec="seconds"), m, flush=True)
def avisar(titulo, cuerpo, p1=True):
    def f():
        try:
            m = EmailMessage(); m["Subject"], m["From"], m["To"] = titulo, "accesos@alcaldia.lab", "ti@alcaldia.lab"; m.set_content(cuerpo)
            with smtplib.SMTP("10.10.20.32", 1025, timeout=8) as s: s.send_message(m)
        except Exception as ex: log(f"aviso por correo falló: {ex}")
        if not (p1 and E("GLPI_PASS")): return
        try:
            U = "http://10.10.20.31/apirest.php"
            def r(p, b=None, h=None): return json.loads(urllib.request.urlopen(urllib.request.Request(U + p, json.dumps(b).encode() if b else None, {"Content-Type": "application/json", **(h or {})}), timeout=10).read() or "null")
            tk = r("/initSession", h={"Authorization": "Basic " + base64.b64encode(("accesos:" + E("GLPI_PASS")).encode()).decode()})["session_token"]
            log(f"ticket GLPI #{r('/Ticket', {'input': {'name': titulo, 'content': html.escape(cuerpo).replace(chr(10), '<br>'), 'type': 1, 'urgency': 5, 'impact': 5}}, {'Session-Token': tk})['id']}")
            r("/killSession", h={"Session-Token": tk})
        except Exception as ex: log(f"ticket GLPI falló: {ex}")
    threading.Thread(target=f, daemon=True).start()
def limpieza():   # borra las caducadas (ya no valían) y avisa
    while True:
        time.sleep(30)
        try:
            for e in politica(True)[1]:
                if e.get("hasta", 0) <= time.time():
                    borrar("acc-exc-" + e["id"]); log(f"excepción {e['id']} caducada ({e['para']})"); avisar(f"Acceso de emergencia caducado: {e['para']}", f"Motivo: {e['motivo']}\nAutorizó: {e['por']}", p1=False)
        except Exception as ex: log(f"limpieza: {ex}")
def authelia(headers, url=None):
    f = {k: v for k, v in headers.items() if k.lower() in ("cookie", "authorization", "proxy-authorization", "x-original-url", "x-original-method", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host", "x-forwarded-uri", "x-forwarded-method", "user-agent")}
    if url: f = {"Cookie": headers.get("Cookie", ""), "X-Original-URL": url, "X-Original-Method": "GET", "User-Agent": headers.get("User-Agent", "")}
    class N(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k): return None
    try: r = urllib.request.build_opener(N).open(urllib.request.Request(AUTHELIA + "/api/authz/auth-request", headers=f), timeout=5); return r.status, r.headers
    except urllib.error.HTTPError as e: return e.code, e.headers
h = html.escape
def pagina(t, b): return (f'<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{t}</title><style>body{{font-family:sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;line-height:1.5}}'
    f'table{{border-collapse:collapse;width:100%}}td,th{{border:1px solid #ccc;padding:.4rem;text-align:left}}input,select,button{{padding:.35rem;margin:.1rem}}</style><body><h1>{t}</h1>{b}</body></html>').encode()
def panel(u, rol, msg=""):
    ho, x = politica(True); fh = lambda s: datetime.datetime.fromtimestamp(s, TZ).strftime("%d/%m %H:%M")
    b = f"<p>Sesión: <b>{h(u)}</b> ({rol})</p>" + (f"<p><b>{h(msg)}</b></p>" if msg else "") + "<h2>Accesos de emergencia activos</h2><table><tr><th>Para</th><th>Hasta</th><th>Motivo</th><th>Autorizó</th><th></th></tr>"
    for e in x:
        if e.get("hasta", 0) > time.time():
            q = f'<form method="post"><input type="hidden" name="accion" value="revocar"><input type="hidden" name="id" value="{h(e["id"])}"><button>Revocar</button></form>' if rol == "rol-admin" or e.get("por") == u else ""
            b += f"<tr><td>{h(e['para'])}</td><td>{fh(e['hasta'])}</td><td>{h(e['motivo'])}</td><td>{h(e['por'])}</td><td>{q}</td></tr>"
    quien = '<option value="grupo:rol-soporte">Todo Soporte</option>' + ('<option value="grupo:funcionarios">Todos los empleados</option>' if rol == "rol-admin" else "")
    b += (f'</table><h2>Dar acceso de emergencia</h2><form method="post"><input type="hidden" name="accion" value="dar"><select name="para">{quien}<option value="usuario">Una persona…</option></select>'
          f'<input name="usuario" placeholder="usuario (si es una persona)"><input name="horas" type="number" min="1" max="{MAX_H[rol]}" value="4" required> horas (máx. {MAX_H[rol]})<br><input name="motivo" required minlength="8" maxlength="200" size="60" placeholder="Motivo"><button>Dar acceso</button></form><h2>Horario normal</h2>')
    for g, v in ho["horarios"].items():
        if rol != "rol-admin": b += f"<p><b>{h(g)}</b>: {h(texto(v))}</p>"; continue
        ch = "".join(f'<label><input type="checkbox" name="d" value="{i}" {"checked" if i in v["dias"] else ""}>{n}</label> ' for i, n in enumerate("L M X J V S D".split(), 1))
        b += f'<form method="post"><input type="hidden" name="accion" value="horario"><input type="hidden" name="grupo" value="{h(g)}"><b>{h(g)}</b> {ch}<input type="time" name="desde" value="{v["desde"]}"> a <input type="time" name="hasta" value="{v["hasta"]}"><button>Guardar</button></form>'
    return pagina("Accesos del personal", b + "<p>rol-admin, rol-ti y acceso-24h no tienen horario.</p>")
def accion(u, rol, f):
    a = f.get("accion", [""])[0]; v = lambda k: f.get(k, [""])[0].strip()
    if a == "dar":
        n = int(v("horas")); mot = v("motivo"); para = v("para")
        if not 1 <= n <= MAX_H[rol]: raise ValueError(f"máximo {MAX_H[rol]} horas para {rol}")
        if not 8 <= len(mot) <= 200: raise ValueError("el motivo debe tener entre 8 y 200 caracteres")
        if para == "usuario":
            q = v("usuario").lower()
            if not re.fullmatch(r"[a-z0-9._-]{1,40}", q): raise ValueError("usuario no válido")
            g = grupos_de(q)
            if not g: raise ValueError("ese usuario no existe o no tiene rol")
            if rol == "rol-ti" and "rol-soporte" not in g: raise ValueError("TI solo puede dar acceso a Soporte")
            para = "usuario:" + q
        elif para not in ("grupo:rol-soporte",) + (("grupo:funcionarios",) if rol == "rol-admin" else ()): raise ValueError("destinatario no permitido")
        if rol == "rol-ti" and any(e["por"] == u and e["hasta"] > time.time() and e["para"] == para for e in politica(True)[1]): raise ValueError("ya hay un acceso suyo activo: no se puede encadenar")
        i = uuid.uuid4().hex[:10]; t = int(time.time()); guardar("acc-exc-" + i, {"para": para, "desde": t, "hasta": t + n * 3600, "motivo": mot, "por": u})
        log(f"AUDITORIA {u} ({rol}) dio acceso a {para} {n} h: {mot}"); avisar(f"[EMERGENCIA] Acceso fuera de horario: {para} ({n} h)", f"Autorizó: {u} ({rol})\nPara: {para}\nHoras: {n}\nMotivo: {mot}"); return f"Acceso concedido a {para} durante {n} h"
    if a == "revocar":
        e = next((e for e in politica(True)[1] if e["id"] == v("id")), None)
        if not e or (rol != "rol-admin" and e["por"] != u): raise ValueError("no permitido")
        borrar("acc-exc-" + e["id"]); log(f"AUDITORIA {u} revocó {e['para']}"); avisar(f"Acceso de emergencia revocado: {e['para']}", f"Revocó: {u}", p1=False); return "Acceso revocado"
    if a == "horario" and rol == "rol-admin":
        ho = json.loads(json.dumps(politica(True)[0])); g = v("grupo"); dias = sorted({int(d) for d in f.get("d", [])})
        if g not in ho["horarios"] or not dias or not all(1 <= d <= 7 for d in dias) or not all(re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", v(k)) for k in ("desde", "hasta")) or v("desde") >= v("hasta"): raise ValueError("horario no válido")
        ho["horarios"][g] = {"dias": dias, "desde": v("desde"), "hasta": v("hasta")}; guardar("acc-horario", ho)
        log(f"AUDITORIA {u} cambió el horario de {g}: {texto(ho['horarios'][g])}"); avisar(f"Horario cambiado: {g}", f"{texto(ho['horarios'][g])}\nPor: {u}", p1=False); return "Horario guardado"
    raise ValueError("acción no permitida")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def resp(self, code, body=b"", hd=()):
        self.send_response(code)
        for k, v in hd: self.send_header(k, v)
        if body: self.send_header("Content-Type", "text/html; charset=utf-8"); self.send_header("X-Frame-Options", "DENY"); self.send_header("Cache-Control", "no-store")
        self.end_headers(); self.wfile.write(body)
    def accesos(self, datos=None):
        try: c, hd = authelia(self.headers, ORIGEN + "/accesos")
        except Exception: return self.resp(503, pagina("No disponible", "<p>No se pudo comprobar la sesión.</p>"))
        if c != 200: return self.resp(302 if hd.get("Location") else c, hd=[(k, x) for k in ("Location", "Set-Cookie") for x in hd.get_all(k) or []])
        u = hd.get("Remote-User", "").lower()
        try: g = grupos_de(u)
        except Exception: return self.resp(503, pagina("No disponible", "<p>No se pudo consultar el directorio.</p>"))
        rol = "rol-admin" if "rol-admin" in g else "rol-ti" if "rol-ti" in g else None
        if not u or not rol: return self.resp(403, pagina("Sin permiso", "<p>Esta página es para administradores y TI.</p>"))
        msg = ""
        if datos is not None:
            if self.headers.get("Origin") != ORIGEN: return self.resp(403, pagina("Origen no válido", ""))
            try:
                with lock: msg = accion(u, rol, datos)
            except Exception as ex: msg = f"No se hizo: {ex}"
        self.resp(200, panel(u, rol, msg))
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); p = urllib.parse.urlparse(self.path).path
        if p == "/accesos" and n <= 8192: return self.accesos(urllib.parse.parse_qs(self.rfile.read(n).decode("utf-8", "replace")))
        self.resp(404)
    def do_GET(self):
        p = urllib.parse.urlparse(self.path)
        if p.path == "/accesos": return self.accesos()
        if p.path == "/authz":
            try: c, hd = authelia(self.headers)
            except Exception as ex: log(f"authelia inaccesible: {ex}"); return self.resp(500)
            if c != 200: return self.resp(c, hd=[(k, x) for k in ("Location", "Set-Cookie") for x in hd.get_all(k) or []])
            u = hd.get("Remote-User", ""); ok, m, _, _ = permitido(u); log(f"authz user={u} ok={ok} motivo={m}")
            return self.resp(200 if ok else 403, hd=[(k, hd[k]) for k in ("Remote-User", "Remote-Groups", "Remote-Name", "Remote-Email") if hd.get(k)] + [("X-Gate-User", u)])
        if p.path == "/denegado":
            u = urllib.parse.parse_qs(p.query).get("u", ["(desconocido)"])[0]; _, m, t, _ = permitido(u)
            b = {"fuera": f"La cuenta <b>{h(u)}</b> puede usar los servicios: <b>{h(m)}</b> (hora de El Salvador)."}.get(t, f"La cuenta <b>{h(u)}</b> no puede entrar: {h(m)}.")
            return self.resp(403, pagina("Acceso no permitido ahora", f"<p>{b}</p><p>Hora actual: <b>{datetime.datetime.now(TZ):%d/%m/%Y %H:%M}</b>.</p><p>En una emergencia, un administrador o TI de guardia puede darle acceso temporal.</p>"))
        self.resp(404)
if __name__ == "__main__":
    threading.Thread(target=limpieza, daemon=True).start()
    http.server.ThreadingHTTPServer(("0.0.0.0", int(E("GATE_PORT", "9200"))), H).serve_forever()
