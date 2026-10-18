#!/usr/bin/env python3
"""live_server.py - Digital Twin MPTCP versi lokal (tanpa aplikasi Claude).

Jalankan di REDLAB:  python3 ~/fssd-proj-2-3/testbed-omr/twin/live_server.py
lalu buka  http://localhost:8765  di browser REDLAB.
Data diambil dari RPi lewat SSH (fungsi yang sama dengan server MCP omr-twin).
Opsi: --host 0.0.0.0 untuk dibuka dari perangkat lain (mis. lewat Tailscale) - hati-hati,
      endpoint start-test ikut terbuka.
"""
import json, os, sys, argparse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
HERE = os.path.dirname(os.path.abspath(__file__))
import types
_src = open(os.path.join(HERE, "omr_twin_mcp.py"), encoding="utf-8").read().split("\nfor raw in sys.stdin:")[0]
omr = types.ModuleType("omr"); exec(compile(_src, "omr_twin_mcp.py", "exec"), omr.__dict__)   # fungsi saja, tanpa loop stdio

SKEL = ('<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
        '<style>:root{color-scheme:light}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>'
        '</head><body>%s</body></html>')

class H(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path)
        if u.path in ("/", "/index.html"):
            html = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
            if not html.lstrip().lower().startswith("<!doctype"): html = SKEL.replace("%s", html)
            return self.send(200, html, "text/html")
        if u.path == "/api/live":
            try:
                since = int(parse_qs(u.query).get("since", ["0"])[0])
                return self.send(200, json.dumps(omr.omr_live({"since": since})))
            except Exception as e:
                return self.send(502, json.dumps({"error": str(e)}))
        self.send(404, json.dumps({"error": "not found"}))
    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/api/start-test":
            try:
                dur = int(parse_qs(u.query).get("duration", ["420"])[0])
                return self.send(200, json.dumps(omr.omr_start_test({"duration": dur})))
            except Exception as e:
                return self.send(502, json.dumps({"error": str(e)}))
        self.send(404, json.dumps({"error": "not found"}))

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--host", default="127.0.0.1"); ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    print(f"Digital Twin live: http://{'localhost' if a.host=='127.0.0.1' else a.host}:{a.port}  (Ctrl+C untuk berhenti)")
    ThreadingHTTPServer((a.host, a.port), H).serve_forever()
