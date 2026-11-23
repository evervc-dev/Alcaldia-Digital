#!/usr/bin/env python3
"""
Prueba de carga básica del portal (RQ-12, Fase 2: 133 sesiones simultáneas en el año 5; 267 en el escenario de 190 sedes).
Cada usuario virtual repite SIN pausa: portada -> consulta de un folio -> formulario de reporte y, 1 de cada 10 vueltas,
envía una solicitud real (nombre «PRUEBA DE CARGA», se borra después). Es mucho más exigente que el modelo de la Fase 3
(una página cada 30 s por sesión): 133 usuarios sin pausa equivalen a miles de sesiones reales.
Uso: prueba-carga.py [usuarios=133] [segundos=60] [pausa_s=0] [url=https://portal.evervc.dev]
     pausa_s > 0: perfil realista (la Fase 3 supone una página cada 30 s por sesión)
"""
import random, ssl, statistics, sys, threading, time, urllib.error, urllib.parse, urllib.request
from collections import Counter, defaultdict

USR = int(sys.argv[1]) if len(sys.argv) > 1 else 133
SEG = int(sys.argv[2]) if len(sys.argv) > 2 else 60
PAUSA = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
URL = sys.argv[4] if len(sys.argv) > 4 else "https://portal.evervc.dev"
lat, codigos, lock = defaultdict(list), Counter(), threading.Lock()
fin = time.time() + SEG
ctx = ssl.create_default_context()

def pedir(nombre, path, datos=None):
    t0 = time.perf_counter()
    try:
        req = urllib.request.Request(URL + path, urllib.parse.urlencode(datos).encode() if datos else None,
                                     {"User-Agent": "ACC-prueba-carga/1.0 (RQ-12)"})
        with urllib.request.urlopen(req, timeout=20, context=ctx) as r:
            r.read(); c = r.status
    except urllib.error.HTTPError as e: c = e.code
    except Exception as e: c = type(e).__name__
    with lock:
        lat[nombre].append(time.perf_counter() - t0); codigos[c] += 1

def usuario(i):
    n = 0
    while time.time() < fin:
        for nom, ruta in (("portada", "/"), ("consulta", "/consulta?folio=R-00000000-PRUEBA"), ("reportar (form)", "/reportar")):
            pedir(nom, ruta)
            if PAUSA: time.sleep(random.uniform(0.5, 1.5) * PAUSA)
        n += 1
        if n % 10 == 0:
            pedir("solicitar (POST)", "/solicitar", {"nombre": "PRUEBA DE CARGA", "documento": "00000000-0",
                                                     "tramite": "Solvencia municipal", "sede": random.choice(["Sede 1", "Sede 2", "Sede 3"])})

print(f"Prueba de carga: {USR} usuarios simultáneos {'sin pausa' if not PAUSA else f'con una página cada ~{PAUSA:.0f} s'} durante {SEG} s contra {URL}")
t0 = time.time()
hilos = [threading.Thread(target=usuario, args=(i,), daemon=True) for i in range(USR)]
for h in hilos: h.start(); time.sleep(0.01 if not PAUSA else PAUSA / USR)   # arranque escalonado
for h in hilos: h.join()
dur = time.time() - t0
todas = [x for v in lat.values() for x in v]
pct = lambda v, p: sorted(v)[min(len(v) - 1, int(len(v) * p))] * 1000
print(f"\nPeticiones: {len(todas)} en {dur:.0f} s = {len(todas) / dur:.1f} pet/s · códigos: {dict(codigos)}")
ok = codigos.get(200, 0) + codigos.get(303, 0)
print(f"Éxito: {100 * ok / max(1, len(todas)):.2f} %")
print(f"{'Página':<20}{'n':>7}{'media':>9}{'p50':>8}{'p95':>8}{'p99':>8}  (ms)")
for k, v in lat.items():
    print(f"{k:<20}{len(v):>7}{statistics.mean(v) * 1000:>9.0f}{pct(v, .5):>8.0f}{pct(v, .95):>8.0f}{pct(v, .99):>8.0f}")
print(f"{'TOTAL':<20}{len(todas):>7}{statistics.mean(todas) * 1000:>9.0f}{pct(todas, .5):>8.0f}{pct(todas, .95):>8.0f}{pct(todas, .99):>8.0f}")
