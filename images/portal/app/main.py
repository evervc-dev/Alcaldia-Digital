"""Portal de trámites - Alcaldía Digital (mínimo funcional para la simulación)."""
import os, html, secrets, datetime
import psycopg
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

DB = os.environ.get("DATABASE_URL", "postgresql://portal@10.10.20.22/portal")
SITE = os.environ.get("PORTAL_SITE", "Site A")
TRAMITES = ["Constancia de residencia", "Solvencia municipal", "Permiso de construcción",
            "Partida de nacimiento", "Licencia de funcionamiento"]
SEDES = ["Sede 1", "Sede 2", "Sede 3"]
app = FastAPI(title="Portal de trámites")

def db():
    return psycopg.connect(DB, connect_timeout=5, autocommit=True)

@app.on_event("startup")
def init():
    try:
        with db() as c:
            c.execute("""CREATE TABLE IF NOT EXISTS tramites(folio text PRIMARY KEY, creado timestamptz DEFAULT now(),
                nombre text, documento text, tramite text, sede text, estado text DEFAULT 'Recibido', atendido_por text)""")
    except Exception as e:
        print("BD no disponible al iniciar:", e, flush=True)

def page(title, body):
    return HTMLResponse(f"""<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>{title} · Alcaldía Digital</title><body style="font-family:sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem;line-height:1.5">
<header style="border-bottom:3px solid #1f4e79;margin-bottom:1rem"><h2 style="color:#1f4e79;margin:0">Alcaldía Digital · Portal de trámites</h2>
<small>Servido desde: <b>{SITE}</b></small></header>{body}
<footer style="margin-top:2rem;color:#777;font-size:.85rem">Centro de Datos Gubernamental · <a href="/consulta">Consultar folio</a> · <a href="/funcionarios">Área de funcionarios</a></footer></body></html>""")

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
    if folio:
        with db() as c:
            r = c.execute("SELECT tramite, sede, estado, creado FROM tramites WHERE folio=%s", (folio,)).fetchone()
        res = (f"<p><b>{html.escape(r[0])}</b> en {html.escape(r[1])}: <b>{html.escape(r[2])}</b> (recibido {r[3]:%d/%m/%Y %H:%M})</p>"
               if r else "<p>Folio no encontrado.</p>")
    return page("Consulta", f"""<h3>Consultar folio</h3><form><input name="folio" value="{html.escape(folio)}"> <button>Consultar</button></form>{res}""")

@app.get("/funcionarios", response_class=HTMLResponse)
def bandeja(request: Request):
    user = request.headers.get("Remote-User", "")
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
    with db() as c:
        c.execute("UPDATE tramites SET estado='En proceso', atendido_por=%s WHERE folio=%s", (request.headers.get("Remote-User", "?"), folio))
    return RedirectResponse("/funcionarios", status_code=303)

@app.get("/salud")
def salud():
    with db() as c:
        n = c.execute("SELECT count(*) FROM tramites").fetchone()[0]
    return {"ok": True, "sitio": SITE, "tramites": n}
