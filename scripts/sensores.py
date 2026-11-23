#!/usr/bin/env python3
"""
Sala de cómputo simulada (GNS3 no emula energía ni ambiente): tarjetas de red de los UPS, generador, ATS y sensores
de temperatura/humedad de los Site A y B, con los valores de diseño de la Fase 3 §4 y los umbrales de la Fase 4 Tabla 13.
Envía una lectura por minuto a Zabbix (trapper, hosts sala-a / sala-b) con zabbix_sender dentro de zbx-server.

Uso:
  sensores.py bucle                      # servicio systemd --user acc-sensores (scripts/tareas-instalar.sh)
  sensores.py <a|b> <escenario>          # inyecta un escenario y envía la lectura en el acto
  sensores.py estado                     # escenario actual y últimas lecturas
Escenarios:
  normal           red comercial, UPS en línea, 22-24 °C, 45-55 % HR
  corte            cae la red: UPS en baterías (P1) -> a los ~20 s arranca el generador y el ATS transfiere (queda «en generador»)
  generador-falla  cae la red y el generador NO arranca: la autonomía baja minuto a minuto (P1, P2 y, < 2 min, P-E)
  calor            falla de un split: la temperatura sube 1 °C/min hasta 32 °C (P2 desde 27 °C)
  humedad          humedad relativa al 85 % (P3)
  sobrecarga       carga de TI de 4,6 kW (aviso de capacidad) y, en A, falla del UPS B: el UPS A queda > 80 % (P2)
  falla-ups-b      (solo A) UPS B fuera de servicio: el UPS A lleva toda la carga (68,6 %)
"""
import json, os, pathlib, random, subprocess, sys, time

ST = pathlib.Path.home() / ".local/state/acc"; ST.mkdir(parents=True, exist_ok=True)
REPO = pathlib.Path(__file__).resolve().parent.parent
UPS_KW = 4.8                                            # SRT5KRMXLT-IEC, 4 800 W (Fase 3, Tabla de UPS)
SITIO = {"a": {"host": "sala-a", "ti": 3.29, "ups": ["a", "b"]},   # carga de TI del Site A: 3,29 kW (Fase 3 §4.1)
         "b": {"host": "sala-b", "ti": 2.29, "ups": ["b1"]}}       # Site B: 2,29 kW, un UPS (Tier I)

def autonomia(w):   # curva del fabricante, recta por (3000 W; 6,12 min) y (3500 W; 4,88 min) — Fase 3 §4.3
    return max(0.0, 6.12 + (3000 - w) * (6.12 - 4.88) / 500)

def pid():
    for f in pathlib.Path.home().glob("GNS3/projects/*/*.gns3"):
        if '"name": "ACC-Lab"' in f.read_text(errors="ignore"): return f.parent.name

def estado(s):
    f = ST / f"sensores-{s}.json"
    try: return json.loads(f.read_text())
    except (OSError, ValueError): return {"escenario": "normal", "desde": time.time()}

def guardar(s, esc):
    (ST / f"sensores-{s}.json").write_text(json.dumps({"escenario": esc, "desde": time.time()}))

def lectura(s):
    cfg, e = SITIO[s], estado(s); esc, t = e["escenario"], time.time() - e["desde"]
    ti = cfg["ti"] * random.uniform(0.97, 1.03)
    temp, hum = random.uniform(22, 24), random.uniform(45, 55)
    red, gen, gen_falla = 1, 0, 0
    servicio = {u: 1 for u in cfg["ups"]}
    bateria = {u: 0 for u in cfg["ups"]}
    if esc == "corte":
        red = 0
        if t < 20: bateria = {u: 1 for u in cfg["ups"]}   # el generador arranca y el ATS transfiere en ~20 s
        else: gen = 1
    elif esc == "generador-falla":
        red, gen_falla = 0, 1; bateria = {u: 1 for u in cfg["ups"]}
    elif esc == "calor":
        temp = min(32.0, 24 + t / 60)
    elif esc == "humedad":
        hum = random.uniform(84, 86)
    elif esc == "sobrecarga":
        ti = 4.6 * random.uniform(0.99, 1.01)
        if s == "a": servicio["b"] = 0
    elif esc == "falla-ups-b" and s == "a":
        servicio["b"] = 0
    activos = [u for u in cfg["ups"] if servicio[u]] or cfg["ups"][:1]
    datos = {"sala.temp": round(temp, 1), "sala.hum": round(hum, 1), "ti.carga": round(ti, 2),
             "red.comercial": red, "gen.marcha": gen, "gen.falla": gen_falla}
    for u in cfg["ups"]:
        w = ti * 1000 / len(activos) if u in activos and servicio[u] else 0.0
        aut = autonomia(w) if w else 0.0
        if bateria[u] and esc == "generador-falla":
            aut = max(0.0, aut - t / 60)                    # la batería se descarga
        datos.update({f"ups.carga[{u}]": round(100 * w / (UPS_KW * 1000), 1), f"ups.autonomia[{u}]": round(aut, 1),
                      f"ups.bateria[{u}]": bateria[u] if servicio[u] else 0, f"ups.servicio[{u}]": servicio[u]})
    return cfg["host"], esc, datos

def enviar(host, datos, p):
    lineas = "".join(f'"{host}" "{k}" {v}\n' for k, v in datos.items())
    r = subprocess.run(["docker", "exec", "-i", f"GNS3.zbx-server.{p}", "zabbix_sender", "-z", "127.0.0.1", "-i", "-"],
                       input=lineas, capture_output=True, text=True)
    return r.returncode == 0

def una(s, p, ver=False):
    host, esc, d = lectura(s); ok = enviar(host, d, p) if p else False
    (ST / f"sensores-{s}.ultima.json").write_text(json.dumps({"escenario": esc, "datos": d, "enviado": ok, "hora": time.strftime("%F %T")}))
    if ver:
        ups = ", ".join(f"UPS {u.upper()} {d[f'ups.carga[{u}]']} %{' EN BATERÍAS' if d[f'ups.bateria[{u}]'] else ''}"
                        f"{' FUERA DE SERVICIO' if not d[f'ups.servicio[{u}]'] else ''} ({d[f'ups.autonomia[{u}]']} min)" for u in SITIO[s]["ups"])
        print(f"{host} [{esc}] {d['sala.temp']} °C, {d['sala.hum']} % HR, TI {d['ti.carga']} kW, red {'sí' if d['red.comercial'] else 'NO'}, "
              f"generador {'en marcha' if d['gen.marcha'] else ('FALLA' if d['gen.falla'] else 'parado')}; {ups} -> Zabbix: {'enviado' if ok else 'NO enviado'}")

if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["bucle"]:
        while True:
            p = pid()
            for s in SITIO:
                try: una(s, p)
                except Exception as ex: print("sensores:", ex, file=sys.stderr)
            time.sleep(60 - time.time() % 60)
    elif a == ["estado"]:
        for s in SITIO:
            try: print(json.loads((ST / f"sensores-{s}.ultima.json").read_text()))
            except OSError: print(s, "sin lecturas")
    elif len(a) == 2 and a[0] in SITIO and a[1] in ("normal", "corte", "generador-falla", "calor", "humedad", "sobrecarga", "falla-ups-b"):
        guardar(a[0], a[1]); una(a[0], pid(), ver=True)
    else:
        print(__doc__); sys.exit(1)
