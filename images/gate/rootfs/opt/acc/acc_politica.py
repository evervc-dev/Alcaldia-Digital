"""Reglas de acceso del personal (una sola implementación para gate, ts1 y puestos).
Datos en el AD, OU=Politica-Acceso, JSON en «info»: acc-horario = {"tz":-6,"horarios":{grupo:{dias,desde,hasta}}}
y acc-exc-<id> = {"para":"usuario:x"|"grupo:rol-soporte","desde":epoch,"hasta":epoch,"motivo":...,"por":...}. La caducidad se
evalúa SIEMPRE por la hora: aunque nadie borre la excepción, deja de valer."""
import datetime, time
EXENTOS = ("rol-admin", "domain admins", "rol-ti", "acceso-24h")
POR_DEFECTO = {"tz": -6, "horarios": {"funcionarios": {"dias": [1, 2, 3, 4, 5], "desde": "07:00", "hasta": "19:00"},
                                      "rol-soporte": {"dias": [1, 2, 3, 4, 5], "desde": "07:00", "hasta": "19:00"}}}
def excepcion(usuario, grupos, excs, ahora=None):
    ahora = ahora or time.time(); obj = {"usuario:" + usuario.lower()} | {"grupo:" + g.lower() for g in grupos}
    v = [e for e in excs if e.get("para", "").lower() in obj and e.get("desde", 0) <= ahora < e.get("hasta", 0)]
    return max(v, key=lambda e: e["hasta"]) if v else None
def evaluar(usuario, grupos, horario, excs, ahora=None):
    """-> (permitido, motivo, tipo)  tipo: exento | horario | excepcion | fuera | sin-rol"""
    ahora = ahora or time.time(); g = {x.lower() for x in grupos}
    for x in EXENTOS:
        if x in g: return True, x, "exento"
    h = {k.lower(): v for k, v in horario.get("horarios", {}).items()}; mios = [k for k in h if k in g]
    t = datetime.datetime.fromtimestamp(ahora, datetime.timezone(datetime.timedelta(hours=horario.get("tz", -6)))); hm = t.strftime("%H:%M")
    for k in mios:
        if t.isoweekday() in h[k]["dias"] and h[k]["desde"] <= hm < h[k]["hasta"]: return True, texto(h[k]), "horario"
    e = excepcion(usuario, grupos, excs, ahora)
    if e: return True, f"excepción hasta {datetime.datetime.fromtimestamp(e['hasta'], t.tzinfo):%d/%m %H:%M} ({e['motivo']})", "excepcion"
    if mios: return False, " o ".join(texto(h[k]) for k in mios), "fuera"
    return False, "la cuenta no tiene un rol asignado", "sin-rol"
D = ("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")
def texto(h):
    d = sorted(h["dias"])
    dias = "todos los días" if len(d) == 7 else f"{D[d[0]-1]} a {D[d[-1]-1]}" if len(d) > 2 and d == list(range(d[0], d[-1] + 1)) else ", ".join(D[i-1] for i in d)
    return f"{dias}, de {h['desde']} a {h['hasta']}"
