"""Portal de trámites - Alcaldía Digital (mínimo funcional para la simulación)."""
import hmac, os, html, secrets, datetime, json, base64, threading, time, urllib.request
import psycopg
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

DB = os.environ.get("DATABASE_URL", "postgresql://portal@10.10.20.22/portal")
SITE = os.environ.get("PORTAL_SITE", "Site A")
TRAMITES = ["Constancia de residencia", "Solvencia municipal", "Permiso de construcción",
            "Partida de nacimiento", "Licencia de funcionamiento"]
SEDES = ["Sede 1", "Sede 2", "Sede 3"]
FALLAS = ["El portal no carga o da error", "No puedo enviar una solicitud", "No encuentro mi folio",
          "Información incorrecta en un trámite", "Otro problema"]
# Mesa de servicio (Fase 4 §2.2): cada reporte ciudadano abre un ticket P4 en GLPI (API interna, cuenta de servicio 'portal')
GLPI_URL = os.environ.get("GLPI_URL", "")            # p. ej. http://10.10.20.31/apirest.php (vacío: solo se guarda)
GLPI_USER, GLPI_PASS = os.environ.get("GLPI_PORTAL_USER", "portal"), os.environ.get("GLPI_PORTAL_PASS", "")
GLPI_CATEGORIA = os.environ.get("GLPI_CATEGORIA", "Portal ciudadano: reporte de falla")
app = FastAPI(title="Portal de trámites")

_ready = False
def db():
    """Conexión a la BD; crea el esquema en la primera conexión correcta (la BD puede arrancar después que el portal)."""
    global _ready
    c = psycopg.connect(DB, connect_timeout=5, autocommit=True)
    if not _ready:
        c.execute("""CREATE TABLE IF NOT EXISTS tramites(folio text PRIMARY KEY, creado timestamptz DEFAULT now(),
            nombre text, documento text, tramite text, sede text, estado text DEFAULT 'Recibido', atendido_por text)""")
        c.execute("""CREATE TABLE IF NOT EXISTS reportes(folio text PRIMARY KEY, creado timestamptz DEFAULT now(),
            nombre text, contacto text, sede text, tipo text, detalle text, ticket int, estado text DEFAULT 'Pendiente de registro')""")
        _ready = True
    return c

def page(title, body):
    return HTMLResponse(f"""<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>{title} · Alcaldía Digital</title><body style="font-family:sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;line-height:1.5">
<header style="border-bottom:3px solid #1f4e79;margin-bottom:1rem"><h2 style="color:#1f4e79;margin:0">Alcaldía Digital · Portal de trámites</h2>
<small>Servido desde: <b>{SITE}</b></small></header>{body}
<footer style="margin-top:2rem;color:#777;font-size:.85rem">Centro de Datos Gubernamental · <a href="/consulta">Consultar folio</a> · <a href="/reportar">Reportar una falla</a> · <a href="/funcionarios">Área de funcionarios</a></footer></body></html>""")

PROXY_SECRET = os.environ.get("PROXY_SECRET", "")
def usuario(request):
    """Usuario autenticado por Authelia. Solo se cree a nginx-dmz, que envía X-Acc-Proxy; sin secreto configurado, a nadie."""
    if not PROXY_SECRET or not hmac.compare_digest(request.headers.get("X-Acc-Proxy", "").encode(), PROXY_SECRET.encode()):
        return ""
    return request.headers.get("Remote-User", "")

@app.get("/", response_class=HTMLResponse)
def inicio():
    opts = "".join(f"<option>{t}</option>" for t in TRAMITES)
    sedes = "".join(f"<option>{s}</option>" for s in SEDES)
    return page("Inicio", f"""<h3>Solicitar un trámite</h3>
<form method="post" action="/solicitar" style="display:grid;gap:.5rem;max-width:420px">
<label>Nombre completo<input name="nombre" required style="width:100%"></label>
<label>Documento (DUI)<input name="documento" required pattern="[0-9-]+" style="width:100%"></label>
<label>Trámite<select name="tramite">{opts}</select></label>
<label>Sede distrital<select name="sede">{sedes}</select></label>
<button>Enviar solicitud</button></form>""")

@app.post("/solicitar", response_class=HTMLResponse)
def solicitar(nombre: str = Form(...), documento: str = Form(...), tramite: str = Form(...), sede: str = Form(...)):
    folio = datetime.date.today().strftime("%Y%m%d-") + secrets.token_hex(3).upper()
    with db() as c:
        c.execute("INSERT INTO tramites(folio,nombre,documento,tramite,sede) VALUES(%s,%s,%s,%s,%s)",
                  (folio, nombre, documento, tramite, sede))
    return page("Solicitud recibida", f"<h3>Solicitud recibida</h3><p>Su folio es <b>{folio}</b>. Consérvelo para dar seguimiento.</p>")

@app.get("/consulta", response_class=HTMLResponse)
def consulta(folio: str = ""):
    res = ""
    if folio.startswith("R-"):
        with db() as c:
            r = c.execute("SELECT tipo, sede, estado, creado, ticket FROM reportes WHERE folio=%s", (folio,)).fetchone()
        res = (f"<p>Reporte <b>{html.escape(r[0])}</b> en {html.escape(r[1])}: <b>{html.escape(r[2])}</b>"
               f"{f' (ticket #{r[4]})' if r[4] else ''} (recibido {r[3].astimezone():%d/%m/%Y %H:%M})</p>" if r else "<p>Folio no encontrado.</p>")
        folio_html = html.escape(folio)
        return page("Consulta", f"""<h3>Consultar folio</h3><form><input name="folio" value="{folio_html}"> <button>Consultar</button></form>{res}""")
    if folio:
        with db() as c:
            r = c.execute("SELECT tramite, sede, estado, creado FROM tramites WHERE folio=%s", (folio,)).fetchone()
        res = (f"<p><b>{html.escape(r[0])}</b> en {html.escape(r[1])}: <b>{html.escape(r[2])}</b> (recibido {r[3].astimezone():%d/%m/%Y %H:%M})</p>"
               if r else "<p>Folio no encontrado.</p>")
    return page("Consulta", f"""<h3>Consultar folio</h3><form><input name="folio" value="{html.escape(folio)}"> <button>Consultar</button></form>{res}""")

# ---------- Reporte ciudadano de fallas -> ticket P4 en GLPI ----------
def glpi(method, path, body=None, token=None, auth=None):
    h = {"Content-Type": "application/json"}
    if token: h["Session-Token"] = token
    if auth: h["Authorization"] = auth
    req = urllib.request.Request(GLPI_URL + path, json.dumps(body).encode() if body is not None else None, h, method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        t = r.read(); return json.loads(t) if t else None

def abrir_ticket(folio, nombre, contacto, sede, tipo, detalle):
    """Crea el ticket (urgencia e impacto bajos -> prioridad Baja = P4 de la Fase 4). Devuelve el n.º o None."""
    if not (GLPI_URL and GLPI_PASS): return None
    tok = glpi("GET", "/initSession", auth="Basic " + base64.b64encode(f"{GLPI_USER}:{GLPI_PASS}".encode()).decode())["session_token"]
    try:
        cat = [int(os.environ["GLPI_CATEGORIA_ID"])] if os.environ.get("GLPI_CATEGORIA_ID", "").isdigit() else []   # Self-Service no lista categorías
        e = lambda x: html.escape(x).replace("\n", "<br>")
        cuerpo = (f"<b>Reporte ciudadano {folio}</b> (portal.evervc.dev)<br>Nombre: {e(nombre)}<br>Contacto: {e(contacto) or '—'}<br>"
                  f"Sede: {e(sede)}<br>Tipo: {e(tipo)}<br><br>{e(detalle)}")
        t = glpi("POST", "/Ticket", {"input": {"name": f"[Portal] {tipo} ({sede}) - {folio}", "content": cuerpo, "type": 1,
                                              "urgency": 2, "impact": 2, **({"itilcategories_id": cat[0]} if cat else {})}}, token=tok)
        return t["id"]
    finally:
        try: glpi("GET", "/killSession", token=tok)
        except Exception: pass

def registrar(folio):
    with db() as c:
        r = c.execute("SELECT nombre, contacto, sede, tipo, detalle FROM reportes WHERE folio=%s AND ticket IS NULL", (folio,)).fetchone()
        if not r: return
        try: n = abrir_ticket(folio, *r)
        except Exception: n = None
        if n: c.execute("UPDATE reportes SET ticket=%s, estado='Registrado en la mesa de servicio' WHERE folio=%s", (n, folio))

def reintentos():   # sin GLPI (caída, o DR en el Site B): los reportes quedan guardados y se registran cuando vuelve
    while True:
        time.sleep(300)
        try:
            with db() as c: pend = [r[0] for r in c.execute("SELECT folio FROM reportes WHERE ticket IS NULL ORDER BY creado LIMIT 20").fetchall()]
            for f in pend: registrar(f)
        except Exception: pass
threading.Thread(target=reintentos, daemon=True).start()

_envios = []   # límite global sencillo contra abuso: 20 reportes por minuto
@app.get("/reportar", response_class=HTMLResponse)
def form_reportar():
    sedes = "".join(f"<option>{s}</option>" for s in SEDES); tipos = "".join(f"<option>{t}</option>" for t in FALLAS)
    return page("Reportar una falla", f"""<h3>Reportar una falla del portal</h3>
<p>Su reporte llega a la <b>mesa de servicio</b> del centro de datos. Recibirá un folio para darle seguimiento.</p>
<form method="post" action="/reportar" style="display:grid;gap:.5rem;max-width:520px">
<label>Nombre<input name="nombre" required maxlength="80" style="width:100%"></label>
<label>Correo o teléfono (opcional)<input name="contacto" maxlength="80" style="width:100%"></label>
<label>Sede distrital<select name="sede">{sedes}</select></label>
<label>¿Qué ocurre?<select name="tipo">{tipos}</select></label>
<label>Detalle<textarea name="detalle" required maxlength="1500" rows="5" style="width:100%"></textarea></label>
<input name="sitio_web" style="display:none" tabindex="-1" autocomplete="off">
<button>Enviar reporte</button></form>""")

@app.post("/reportar", response_class=HTMLResponse)
def reportar(nombre: str = Form(...), detalle: str = Form(...), sede: str = Form(...), tipo: str = Form(...),
             contacto: str = Form(""), sitio_web: str = Form("")):
    if sitio_web:   # campo trampa: solo lo rellenan los robots
        return page("Reporte recibido", "<p>Gracias.</p>")
    now = time.time(); _envios[:] = [t for t in _envios if now - t < 60]
    if len(_envios) >= 20:
        return page("Inténtelo más tarde", "<p>Hay muchos reportes en este momento. Inténtelo de nuevo en un minuto.</p>")
    _envios.append(now)
    sede = sede if sede in SEDES else SEDES[0]; tipo = tipo if tipo in FALLAS else FALLAS[-1]
    folio = "R-" + datetime.date.today().strftime("%Y%m%d-") + secrets.token_hex(3).upper()
    with db() as c:
        c.execute("INSERT INTO reportes(folio,nombre,contacto,sede,tipo,detalle) VALUES(%s,%s,%s,%s,%s,%s)",
                  (folio, nombre[:80], contacto[:80], sede, tipo, detalle[:1500]))
    registrar(folio)
    with db() as c: t = c.execute("SELECT ticket FROM reportes WHERE folio=%s", (folio,)).fetchone()[0]
    extra = (f" Quedó registrado en la mesa de servicio con el ticket <b>#{t}</b>." if t else
             " La mesa de servicio lo registrará en cuanto esté disponible.")
    return page("Reporte recibido", f"<h3>Reporte recibido</h3><p>Su folio es <b>{folio}</b>.{extra}</p>"
                f"<p>Puede consultarlo en <a href='/consulta?folio={folio}'>Consultar folio</a>.</p>")

@app.get("/funcionarios", response_class=HTMLResponse)
def bandeja(request: Request):
    user = usuario(request)
    if not user:
        return page("Acceso", "<p>Esta área requiere iniciar sesión con su cuenta institucional.</p>")
    with db() as c:
        rows = c.execute("SELECT folio, tramite, sede, estado, nombre FROM tramites ORDER BY creado DESC LIMIT 50").fetchall()
    filas = "".join(f"<tr><td>{f}</td><td>{html.escape(t)}</td><td>{s}</td><td>{e}</td><td>{html.escape(n)}</td>"
                    f"<td><form method=post action=/funcionarios/atender style=margin:0><input type=hidden name=folio value={f}><button>Atender</button></form></td></tr>"
                    for f, t, s, e, n in rows)
    return page("Bandeja", f"<h3>Bandeja de trámites</h3><p>Sesión: <b>{html.escape(user)}</b> ({html.escape(request.headers.get('Remote-Groups',''))})</p>"
                f"<table border=1 cellpadding=4 style=border-collapse:collapse><tr><th>Folio</th><th>Trámite</th><th>Sede</th><th>Estado</th><th>Solicitante</th><th></th></tr>{filas}</table>")

@app.post("/funcionarios/atender")
def atender(request: Request, folio: str = Form(...)):
    user = usuario(request)
    if not user:
        return HTMLResponse("Requiere iniciar sesión", status_code=403)
    with db() as c:
        c.execute("UPDATE tramites SET estado='En proceso', atendido_por=%s WHERE folio=%s", (user, folio))
    return RedirectResponse("/funcionarios", status_code=303)

@app.get("/salud")
def salud():
    with db() as c:
        n = c.execute("SELECT count(*) FROM tramites").fetchone()[0]
    return {"ok": True, "sitio": SITE, "tramites": n}
