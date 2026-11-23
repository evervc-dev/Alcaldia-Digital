#!/usr/bin/env python3
"""Política de acceso en ts1 y en los puestos (mismas reglas que gate: acc_politica.py).
agente: (root, cada 30 s) lee OU=Politica-Acceso con la cuenta de máquina y CIERRA las sesiones que entraron por una excepción ya vencida.
comprobar: (usuario, al iniciar sesión) sale 0 si puede entrar; si no, imprime el motivo y sale 1."""
import grp, json, os, pwd, signal, subprocess, sys, time
sys.path.insert(0, "/opt/acc")
from acc_politica import POR_DEFECTO, evaluar
F = "/var/lib/samba/acc/politica.json"; OU = ",ou=politica-acceso,dc=ad,dc=alcaldia,dc=lab"
def leer():
    try: d = json.load(open(F)); return d["h"], d["x"]
    except (OSError, ValueError, KeyError): return POR_DEFECTO, []
def grupos(u):
    r = []
    for g in os.getgrouplist(u, pwd.getpwnam(u).pw_gid):
        try: r.append(grp.getgrgid(g).gr_name.split("\\")[-1].lower())
        except KeyError: pass
    return r
def sincronizar():
    r = subprocess.run(["net", "ads", "search", "-P", "(&(objectClass=group)(cn=acc-*))", "distinguishedName", "cn", "info"], capture_output=True, text=True, timeout=20)
    if r.returncode: return
    h, x = POR_DEFECTO, []
    for bloque in r.stdout.split("\n\n"):      # un objeto por bloque; el orden de los atributos no está garantizado
        o = dict(l.partition(": ")[::2] for l in bloque.splitlines() if ": " in l); cn = o.get("cn", "")
        if not o.get("distinguishedName", "").lower().endswith(OU): continue      # solo objetos de esa OU (nadie más puede inventarlos)
        try: d = json.loads(o.get("info", ""))
        except ValueError: continue
        if cn == "acc-horario": h = d
        elif cn.startswith("acc-exc-"): x.append(d)
    os.makedirs(os.path.dirname(F), exist_ok=True); t = F + ".n"; json.dump({"h": h, "x": x, "t": time.time()}, open(t, "w")); os.chmod(t, 0o644); os.replace(t, F)
def sesiones():
    s = {}
    for p in filter(str.isdigit, os.listdir("/proc")):
        try:
            if open(f"/proc/{p}/comm").read().strip() in ("xfce4-session", "startxfce4"): s.setdefault(pwd.getpwuid(os.stat(f"/proc/{p}").st_uid).pw_name, []).append(int(p))
        except (OSError, KeyError): pass
    return s
def cerrar(u):
    uid = pwd.getpwnam(u).pw_uid
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for p in filter(str.isdigit, os.listdir("/proc")):
            try:
                if os.stat(f"/proc/{p}").st_uid == uid: os.kill(int(p), sig)
            except OSError: pass
        time.sleep(3)
def agente():
    por_exc = set()
    while True:
        try:
            sincronizar(); h, x = leer(); vivas = set(sesiones())
            for u in vivas:
                ok, m, t = evaluar(u, grupos(u), h, x)
                if t == "excepcion": por_exc.add(u)
                elif ok: por_exc.discard(u)
                elif u in por_exc:
                    open("/var/log/acc-horario.log", "a").write(f"{time.strftime('%FT%T')} user={u} SESIÓN CERRADA: venció su acceso de emergencia\n"); cerrar(u); por_exc.discard(u)
            por_exc &= vivas
        except Exception as e: print("acc-acceso:", e, flush=True)
        time.sleep(30)
if sys.argv[1:] == ["agente"]: agente()
else:
    u = pwd.getpwuid(os.getuid()).pw_name; ok, m, t = evaluar(u, grupos(u), *leer())
    open("/var/log/acc-horario.log", "a").write(f"{time.strftime('%FT%T')} user={u} {'permitido' if ok else 'DENEGADO'} ({m})\n"); print(m); sys.exit(0 if ok else 1)
