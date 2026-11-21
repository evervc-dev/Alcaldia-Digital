#!/usr/bin/env python3
"""Utilidad para nodos QEMU de GNS3 sin consola serie (OPNsense nano usa VGA).
Uso:
  qemu-monitor.py NODO screen SALIDA.png      captura la pantalla VGA
  qemu-monitor.py NODO keys "texto" [enter]   escribe texto con sendkey
  qemu-monitor.py NODO cmd "info status"      comando arbitrario del monitor
El puerto del monitor se obtiene del proceso qemu (-name NODO -monitor tcp:127.0.0.1:PUERTO)."""
import re, socket, subprocess, sys, time, os, tempfile

def port(node):
    out = subprocess.run(["ps", "-C", "qemu-system-x86_64", "-o", "args="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if f"-name {node} " in line:
            m = re.search(r"-monitor tcp:127\.0\.0\.1:(\d+)", line)
            if m: return int(m.group(1))
    sys.exit(f"nodo QEMU '{node}' no encontrado o sin monitor")

def mon(node, cmds, delay=0.15):
    s = socket.create_connection(("127.0.0.1", port(node))); time.sleep(0.3); s.recv(65536)
    for c in cmds:
        s.sendall((c + "\n").encode()); time.sleep(delay)
    time.sleep(0.5); s.close()

KEYMAP = {" ": "spc", "\n": "ret", ".": "dot", "-": "minus", "/": "slash", ",": "comma", "=": "equal",
          ";": "semicolon", "'": "apostrophe", "\\": "backslash", "_": "shift-minus", ":": "shift-semicolon",
          "@": "shift-2", "!": "shift-1", "#": "shift-3", "$": "shift-4", "%": "shift-5", "&": "shift-7",
          "*": "shift-8", "(": "shift-9", ")": "shift-0", "+": "shift-equal", '"': "shift-apostrophe",
          "|": "shift-backslash", "<": "shift-comma", ">": "shift-dot", "?": "shift-slash"}

def key(ch):
    if ch in KEYMAP: return KEYMAP[ch]
    if ch.isupper(): return "shift-" + ch.lower()
    return ch

if __name__ == "__main__":
    node, action = sys.argv[1], sys.argv[2]
    if action == "screen":
        out = sys.argv[3]; ppm = tempfile.mktemp(suffix=".ppm")
        mon(node, [f"screendump {ppm}"]); time.sleep(0.5)
        from PIL import Image
        Image.open(ppm).save(out); os.remove(ppm); print(out)
    elif action == "keys":
        text = sys.argv[3] + ("\n" if len(sys.argv) > 4 and sys.argv[4] == "enter" else "")
        mon(node, [f"sendkey {key(c)}" for c in text], delay=0.08)
    elif action == "cmd":
        mon(node, [sys.argv[3]])
