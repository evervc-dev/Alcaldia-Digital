#!/bin/bash
# Muestra el último código de identidad que Authelia envió a un usuario (queda en mailpit mientras no haya correo real). Solo para quien administra el lab.
# Uso: codigo-mfa.sh <usuario>
set -euo pipefail; U=${1:?usuario}; [[ $U =~ ^[a-z0-9._-]+$ ]] || exit 1
PID=$(grep -l '"name": "ACC-Lab"' ~/GNS3/projects/*/*.gns3 | head -1 | xargs dirname | xargs basename)
docker exec -i "GNS3.portal.$PID" python3 - "$U" <<'PY'
import json,re,sys,urllib.request,datetime
g=lambda p: json.load(urllib.request.urlopen("http://10.10.20.32:8025/api/v1/"+p,timeout=8))
ms=[m for m in g("search?query=subject:Confirm&limit=50")["messages"] if any(t["Address"].split("@")[0].lower()==sys.argv[1] for t in m["To"])]
if not ms: sys.exit("no hay correos de identidad para "+sys.argv[1])
m=max(ms,key=lambda x:x["Created"]); t=g("message/"+m["ID"])["Text"]
edad=(datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat(m["Created"][:19]+"+00:00")).seconds//60
c=re.findall(r"(?m)^\s*([A-Z0-9]{6,10})\s*$",t)
print("Código:",c[0] if c else "(no reconocido)\n"+t,f"— enviado hace {edad} min",("(CADUCADO: pida otro)" if edad>=5 else ""))
PY
