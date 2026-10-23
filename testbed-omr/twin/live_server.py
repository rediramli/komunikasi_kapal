#!/usr/bin/env python3
"""live_server.py - local server for the Digital Twin MPTCP page.

Run on REDLAB:  python3 ~/fssd-proj-2-3/testbed-omr/twin/live_server.py
then open       http://localhost:8799
Data and control go to the RPi over SSH (key login, same as run.sh).

Endpoints
  GET  /                              the page (twin/index.html)
  GET  /api/live?since=EPOCH          1 Hz samples from the RPi (+ manual cut flags/events)
  POST /api/start-test?duration=S     automatic failover test (failover-test.sh)
  GET  /api/sched                     active scheduler, list, switch history
  POST /api/sched?name=X&restart=1    switch scheduler (sysctl, not persistent) + restart OpenVPN
  GET  /api/link                      manual cut state + endpoint backup flags
  POST /api/link?dev=wan1&action=cut&secs=120   simulate signal loss on one link (auto-restores)
  POST /api/link?dev=wan1&action=restore
  POST /api/prio?mode=auto|simba|singtel        MPTCP endpoint backup flags (primary path)

Options: --port 8799  --host 127.0.0.1  --rpi root@100.102.109.59
Keep --host on 127.0.0.1: the control endpoints change the RPi.
"""
import json, os, re, sys, time, argparse, subprocess, threading, base64
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

AUTH = os.environ.get("TWIN_AUTH", "")   # set to "user:password" to require HTTP Basic auth (for public hosting)
HERE = os.path.dirname(os.path.abspath(__file__))
import types
_src = open(os.path.join(HERE, "omr_twin_mcp.py"), encoding="utf-8").read().split("\nfor raw in sys.stdin:")[0]
omr = types.ModuleType("omr"); exec(compile(_src, "omr_twin_mcp.py", "exec"), omr.__dict__)   # functions only, no stdio loop

RPI = "root@100.102.109.59"
SCHED_LOG = "/tmp/omr_sched.log"          # on the RPi: "<epoch> <scheduler> [init]" per line; cleared on reboot
LINKS = {"wan1": {"name": "Simba", "net": "192.168.1.0/24", "col": 7},
         "wan2": {"name": "Singtel", "net": "192.168.2.0/24", "col": 8}}
LOCK = threading.Lock()
CUTS = {"wan1": [], "wan2": []}           # [start_epoch, end_epoch|None, planned_end]
MANUAL = []                               # [{"ep":..,"dev":..,"kind":"down"|"up","how":"manual"|"auto-restore"}]

def rpi(cmd, timeout=30):
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", RPI, cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr

VPS = "root@168.144.105.155"
VPS_PORT = "65222"
def vps(cmd, timeout=30):
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-p", VPS_PORT, VPS, cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr

# ---------------- Jetson multipath: split control + load test ----------------
MPTUN_CTL = "/tmp/mptun_w"          # the pinned-path split (0=all Singtel .. 1=all Simba)
SIGMA_KBPS = 32600                  # measured sum of the two SIM capacities (ceiling)
LOAD_PORT = 5301                    # Stage-3 load-test proxy port on the VPS

def split_status():
    rc, out, err = rpi("cat %s 2>/dev/null || echo 0.5" % MPTUN_CTL)
    try: w = float(out.strip())
    except Exception: w = 0.5
    return {"w": w, "sigma_kbps": SIGMA_KBPS}

def split_set(w):
    w = max(0.0, min(1.0, float(w)))
    rpi("echo %.3f > %s" % (w, MPTUN_CTL))
    return {"ok": True, "w": w}

JET_DECISION = "/tmp/jet_decision.json"   # edge_control.py on the Jetson writes its live decision here (via the RPi)
def jet_status():
    """The Jetson AI's latest decision snapshot: observed state, per-split scores, chosen (N,w)."""
    rc, out, err = rpi("cat %s 2>/dev/null || echo '{}'" % JET_DECISION)
    try: d = json.loads((out or "").strip() or "{}")
    except Exception: d = {}
    d["sigma_kbps"] = SIGMA_KBPS
    return d

def loadtest(action, secs, mbps):
    secs = max(5, min(60, int(secs))); mbps = max(0.0, min(40.0, float(mbps)))
    if action == "stop":
        rpi('P=mpproxy""_send; pkill -f "$P" 2>/dev/null; true')
        return {"ok": True, "state": "stopped"}
    # open the port, start a fresh receiver, wait until it listens, then the sender
    vps('nft list chain inet omr input 2>/dev/null | grep -q "dport %d" || '
        'nft insert rule inet omr input tcp dport %d accept comment "loadtest"' % (LOAD_PORT, LOAD_PORT))
    # free the port by pid (name-based pkill would self-match this very command), then start
    vps('for p in $(ss -tlnp 2>/dev/null | grep ":%d " | grep -oE "pid=[0-9]+" | cut -d= -f2); do kill -9 $p 2>/dev/null; done; sleep 0.4; '
        'setsid python3 /tmp/mpproxy_recv.py --port %d --conns 8 >/tmp/recv.json 2>/dev/null </dev/null & echo up' % (LOAD_PORT, LOAD_PORT))
    listening = False
    for _ in range(10):
        time.sleep(0.5)
        rc, out, err = vps("ss -tln 2>/dev/null | grep -c :%d" % LOAD_PORT)
        if out.strip() not in ("", "0"):
            listening = True; break
    if not listening:
        raise ValueError("load-test receiver did not start on the VPS")
    rpi('setsid python3 /tmp/mpproxy_send.py --host 168.144.105.155 --port %d --n1 4 --n2 4 '
        '--w 0.5 --dur %d --bitrate %g --strict --ctl %s >/tmp/send.out 2>&1 </dev/null & echo started'
        % (LOAD_PORT, secs, mbps, MPTUN_CTL))
    return {"ok": True, "state": "running", "secs": secs, "mbps": mbps}

# ---------------- VPN / transport switch (Glorytun UDP vs Glorytun TCP/MPTCP) ----------------
VPN_DEF = {
  "glorytun_udp": {"label": "Glorytun UDP",        "mptcp": False, "rpi_ip": "10.255.254.2",
                   "vps_route": "ip route replace 192.168.100.0/24 via 10.255.254.2 dev gt-udp-tun0"},
  "glorytun_tcp": {"label": "Glorytun TCP (MPTCP)", "mptcp": True,  "rpi_ip": "10.255.255.2",
                   "vps_route": "ip route replace 192.168.100.0/24 via 10.255.255.2 dev gt-tun0"},
}
def vpn_status():
    rc, out, err = rpi("uci -q get openmptcprouter.settings.vpn; uci -q get openmptcprouter.omr.vpn; "
                       "ss -tniM 2>/dev/null | grep -c subflows_total:2", 15)
    if rc != 0 and not out:
        raise RuntimeError((err or "ssh to RPi failed").strip()[:200])
    p = (out.splitlines() + ["", "", ""])
    return {"current": p[0].strip(), "status": p[1].strip(),
            "available": list(VPN_DEF), "labels": {k: v["label"] for k, v in VPN_DEF.items()},
            "mptcp": VPN_DEF.get(p[0].strip(), {}).get("mptcp", False)}

def vpn_set(name):
    if name not in VPN_DEF:
        raise ValueError("unknown vpn: %r" % name)
    # Each glorytun variant puts its peer IP on a tun device, but OMR also runs OpenVPN on
    # tun0 (10.255.252.x). OpenVPN can re-grab tun0 and make glorytun fail with "couldn't
    # create tun device", leaving the interface + IP present but the DAEMON dead (tunnel up
    # on paper, no data plane -> camera stops). So stop OpenVPN, delete the stale device,
    # then verify the daemon is actually alive (pidof, self-match-proof) with a few retries
    # -- not just that tun0 exists, which previously gave a false "done".
    if name == "glorytun_tcp":
        on, off, svc_on, svc_off = "glorytun", "glorytun-udp", "glorytun", "glorytun-udp"
        proc, dev, waitip = "glorytun-tcp", "tun0", "10.255.255.2"
        free = "/etc/init.d/openvpn stop >/dev/null 2>&1; ip link del gt-tun0 2>/dev/null; ip link del tun0 2>/dev/null"
        ipcmd = "ip addr add 10.255.255.2/32 peer 10.255.255.1 dev tun0 2>/dev/null; ip link set tun0 up"
    else:
        on, off, svc_on, svc_off = "glorytun-udp", "glorytun", "glorytun-udp", "glorytun"
        proc, dev, waitip = "glorytun-udp", "tun0", "10.255.254.2"
        free = "/etc/init.d/openvpn stop >/dev/null 2>&1; ip link del tun0 2>/dev/null"
        ipcmd = "ip addr add 10.255.254.2/32 peer 10.255.254.1 dev tun0 2>/dev/null; ip link set tun0 up"
    rcmd = ("uci set openmptcprouter.settings.vpn=%(name)s; "
            "uci set %(on)s.vpn.enable=1; uci set %(off)s.vpn.enable=0; uci commit; "
            "/etc/init.d/%(svcoff)s stop >/dev/null 2>&1; "
            "n=0; while :; do %(free)s; sleep 1; /etc/init.d/%(svcon)s restart >/dev/null 2>&1; "
            "ok=0; for i in $(seq 1 12); do pidof %(proc)s >/dev/null 2>&1 && { ok=1; break; }; sleep 1; done; "
            "[ \"$ok\" = 1 ] && break; n=$((n+1)); [ $n -ge 3 ] && break; done; "
            "for i in $(seq 1 15); do ip link show %(dev)s >/dev/null 2>&1 && break; sleep 1; done; sleep 1; %(ipcmd)s; "
            "for i in $(seq 1 15); do ip addr show %(dev)s 2>/dev/null | grep -q %(waitip)s && break; sleep 1; done; "
            "if pidof %(proc)s >/dev/null 2>&1 && ip addr show %(dev)s 2>/dev/null | grep -q %(waitip)s; then echo done; else echo FAIL; fi"
            % {"name": name, "on": on, "off": off, "svcoff": svc_off, "svcon": svc_on,
               "free": free, "proc": proc, "dev": dev, "ipcmd": ipcmd, "waitip": waitip})
    rc, out, err = rpi(rcmd, 180)
    if "done" not in out:
        raise RuntimeError((err or out).strip()[:200] or "vpn switch failed: glorytun daemon not alive on RPi")
    vps(VPN_DEF[name]["vps_route"], 30)
    time.sleep(2)
    st = vpn_status()
    st["ok"] = (st["current"] == name)
    return st

# ---------------- sampler ----------------
_last_kick = [0]
def ensure_sampler():
    """Start the RPi 1 Hz sampler detached from the SSH session if it is not running (max once per 20 s)."""
    if time.time() - _last_kick[0] < 20: return
    _last_kick[0] = time.time()
    try:
        rpi("pgrep -f omr-live.sh >/dev/null || { S=; command -v setsid >/dev/null && S=setsid; "
            "( $S sh /root/omr-live.sh </dev/null >/dev/null 2>&1 & ) ; }", 15)
    except Exception:
        pass

# ---------------- scheduler ----------------
def sched_status():
    cmd = ("[ -s %s ] || echo \"$(date +%%s) $(sysctl -n net.mptcp.scheduler) init\" > %s; "
           "sysctl -n net.mptcp.scheduler; sysctl -n net.mptcp.available_schedulers; date +%%s; tail -n 200 %s"
           % (SCHED_LOG, SCHED_LOG, SCHED_LOG))
    rc, out, err = rpi(cmd, 20)
    lines = out.splitlines()
    if rc != 0 or len(lines) < 3:
        raise RuntimeError((err or out).strip()[:200] or "ssh to RPi failed")
    log = []
    for l in lines[3:]:
        p = l.split()
        if len(p) >= 2 and p[0].isdigit():
            log.append([int(p[0]), p[1]] + ([1] if len(p) > 2 and p[2] == "init" else []))
    return {"current": lines[0].strip(), "available": lines[1].split(), "now": int(lines[2]), "log": log}

BLOCKED_SCHED = {"bpf_red"}   # redundant mode deadlocks/breaks the OpenVPN --mptcp tunnel on this kernel

def sched_set(name, restart=True):
    st = sched_status()
    if not re.fullmatch(r"[a-z0-9_]{1,32}", name or "") or name not in st["available"]:
        raise ValueError("unknown scheduler: %r" % name)
    if name in BLOCKED_SCHED:
        raise ValueError("%s is disabled: redundant mode breaks the OpenVPN tunnel handshake on this kernel "
                         "(tun0 never comes up; it took a VPS reboot to recover). Use default/blest." % name)
    cmd = ("sysctl -w net.mptcp.scheduler=%s >/dev/null && echo \"$(date +%%s) %s\" >> %s && "
           "logger -t omr-twin \"scheduler -> %s\"" % (name, name, SCHED_LOG, name))
    if restart:
        # restart whichever VPN actually carries the camera so the new scheduler takes effect
        cmd += (" && V=$(uci -q get openmptcprouter.settings.vpn);"
                " case \"$V\" in"
                " glorytun_tcp) /etc/init.d/glorytun restart >/dev/null 2>&1; sh /root/gt-tcp-ip.sh >/dev/null 2>&1 ;;"
                " glorytun_udp) /etc/init.d/glorytun-udp restart >/dev/null 2>&1 ;;"
                " *) /etc/init.d/openvpn restart >/dev/null 2>&1 ;;"
                " esac; echo done")
    rc, out, err = rpi(cmd, 60)
    if "done" not in out and rc != 0:
        raise RuntimeError((err or out).strip()[:200] or "failed")
    st = sched_status()
    st.update({"ok": st["current"] == name, "restarted": bool(restart)})
    if not st["ok"]:
        st["error"] = "sysctl did not change (active: %s)" % st["current"]
    return st

# ---------------- link cut / priority ----------------
RESTORE_SH = ('cat > /tmp/twincut_restore.sh <<\'EOS\'\n'
              'sleep "$3"; [ "$(cat /tmp/$1.id 2>/dev/null)" = "$2" ] && nft delete table inet $1 2>/dev/null\n'
              'logger -t omr-twin "auto-restore $1"; exit 0\nEOS\n')

def link_status():
    rc, out, err = rpi("date +%s; echo ---; nft list tables 2>/dev/null | grep -o 'twincut_wan[12]'; "
                       "echo ---; ip mptcp endpoint show", 20)
    if rc != 0 or "---" not in out:
        raise RuntimeError((err or out).strip()[:200] or "ssh to RPi failed")
    parts = out.split("---")
    now = int(parts[0].strip())
    cut = {d: ("twincut_" + d) in parts[1] for d in LINKS}
    prio, eps = {}, {}
    for line in parts[2].splitlines():
        m = re.search(r"\bid (\d+)\b.*\bdev (wan[12])\b", line)
        if m:
            eps[m.group(2)] = int(m.group(1))
            prio[m.group(2)] = "backup" if re.search(r"\bbackup\b", line) else "normal"
    with LOCK:   # sync our cut intervals with what the RPi really has (auto-restore happens there)
        for d in LINKS:
            open_iv = CUTS[d] and CUTS[d][-1][1] is None
            if cut[d] and not open_iv:
                CUTS[d].append([now, None, now]); MANUAL.append({"ep": now, "dev": d, "kind": "down", "how": "manual"})
            elif not cut[d] and open_iv:
                end = min(now, CUTS[d][-1][2]); CUTS[d][-1][1] = end
                MANUAL.append({"ep": end, "dev": d, "kind": "up", "how": "auto-restore"})
    mode = "auto"
    if prio.get("wan2") == "backup" and prio.get("wan1") != "backup": mode = "simba"
    if prio.get("wan1") == "backup" and prio.get("wan2") != "backup": mode = "singtel"
    return {"now": now, "cut": cut, "prio": prio, "mode": mode, "endpoints": eps}

def link_cut(dev, secs):
    if dev not in LINKS: raise ValueError("unknown link")
    secs = max(15, min(int(secs), 1800))
    st = link_status()
    other = "wan2" if dev == "wan1" else "wan1"
    if st["cut"][other]:
        raise ValueError("%s is already cut. Cutting both links would also cut REDLAB's SSH/Tailscale access to the RPi."
                         % LINKS[other]["name"])
    if st["cut"][dev]:
        return st
    t, net = "twincut_" + dev, LINKS[dev]["net"]
    cmd = (RESTORE_SH +
           "nft -f - <<'EON'\n"
           "table inet %(t)s {\n"
           " chain o { type filter hook output priority -5; policy accept; oifname \"%(d)s\" ip daddr != %(n)s drop; }\n"
           " chain i { type filter hook input priority -5; policy accept; iifname \"%(d)s\" ip saddr != %(n)s drop; }\n"
           " chain f { type filter hook forward priority -5; policy accept; oifname \"%(d)s\" ip daddr != %(n)s drop; "
           "iifname \"%(d)s\" ip saddr != %(n)s drop; }\n"
           "}\nEON\n"
           "id=$(date +%%s); echo $id > /tmp/%(t)s.id; logger -t omr-twin \"cut %(d)s for %(s)ss\"\n"
           "S=; command -v setsid >/dev/null && S=setsid; ( $S sh /tmp/twincut_restore.sh %(t)s $id %(s)s </dev/null >/dev/null 2>&1 & )\n"
           "echo cut-ok $id\n") % {"t": t, "d": dev, "n": net, "s": secs}
    rc, out, err = rpi(cmd, 30)
    m = re.search(r"cut-ok (\d+)", out)
    if not m:
        raise RuntimeError((err or out).strip()[:200] or "cut failed")
    ep = int(m.group(1))
    with LOCK:
        if not (CUTS[dev] and CUTS[dev][-1][1] is None):
            CUTS[dev].append([ep, None, ep + secs]); MANUAL.append({"ep": ep, "dev": dev, "kind": "down", "how": "manual"})
        else:
            CUTS[dev][-1][2] = ep + secs
    return link_status()

def link_restore(dev):
    if dev not in LINKS: raise ValueError("unknown link")
    t = "twincut_" + dev
    rc, out, err = rpi("rm -f /tmp/%s.id; nft delete table inet %s 2>/dev/null; logger -t omr-twin \"restore %s\"; date +%%s"
                       % (t, t, dev), 20)
    ep = int(out.strip().splitlines()[-1]) if out.strip() else int(time.time())
    with LOCK:
        if CUTS[dev] and CUTS[dev][-1][1] is None:
            CUTS[dev][-1][1] = ep; MANUAL.append({"ep": ep, "dev": dev, "kind": "up", "how": "manual"})
    return link_status()

def set_prio(mode):
    want = {"auto": {"wan1": "nobackup", "wan2": "nobackup"},
            "simba": {"wan1": "nobackup", "wan2": "backup"},
            "singtel": {"wan1": "backup", "wan2": "nobackup"}}.get(mode)
    if not want: raise ValueError("mode must be auto, simba or singtel")
    st = link_status()
    cmds = []
    for d, flag in want.items():
        if d not in st["endpoints"]:
            raise RuntimeError("no MPTCP endpoint for %s (ip mptcp endpoint show)" % d)
        cmds.append("ip mptcp endpoint change id %d %s" % (st["endpoints"][d], flag))
    rc, out, err = rpi(" && ".join(cmds) + " && logger -t omr-twin \"prio %s\" && echo prio-ok" % mode, 20)
    if "prio-ok" not in out:
        raise RuntimeError((err or out).strip()[:200] or "ip mptcp endpoint change failed")
    return link_status()

def overlay(res):
    """Mark manually cut seconds in the sample rows (cols 7/8) and attach manual events."""
    with LOCK:
        cuts = {d: [list(iv) for iv in CUTS[d]] for d in LINKS}
        res["manual"] = list(MANUAL[-100:])
    rows = res.get("rows") or []
    for r in rows:
        while len(r) < 9: r.append(0)
        for d, info in LINKS.items():
            for s, e, _ in cuts[d]:
                if r[0] >= s and (e is None or r[0] < e):
                    r[info["col"]] = 1; break
    return res

# ---------------- HTTP ----------------
SKEL = ('<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>body{margin:0}[hidden]{display:none!important}</style></head><body>%s</body></html>')

class H(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(b)))
        try:
            self.end_headers(); self.wfile.write(b)
        except (BrokenPipeError, ConnectionResetError):
            pass   # browser closed the request (reload/navigate) - harmless
    def log_message(self, *a): pass
    def _auth_ok(self):
        if not AUTH: return True
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            try:
                if base64.b64decode(h[6:]).decode("utf-8", "ignore") == AUTH: return True
            except Exception: pass
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Digital Twin MPTCP"')
        self.send_header("Content-Length", "0"); self.end_headers()
        return False
    def run(self, fn):
        try: return self.send(200, json.dumps(fn()))
        except ValueError as e: return self.send(400, json.dumps({"ok": False, "error": str(e)}))
        except Exception as e: return self.send(502, json.dumps({"ok": False, "error": str(e)}))
    def do_GET(self):
        if not self._auth_ok(): return
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path in ("/", "/index.html"):
            html = open(os.path.join(HERE, "index.html"), encoding="utf-8").read()
            if not html.lstrip().lower().startswith("<!doctype"): html = SKEL.replace("%s", html)
            return self.send(200, html, "text/html")
        if u.path == "/api/live":
            def live():
                res = omr.omr_live({"since": int(q.get("since", ["0"])[0])})
                if not res.get("rows"): ensure_sampler()
                return overlay(res)
            return self.run(live)
        if u.path == "/api/sched": return self.run(sched_status)
        if u.path == "/api/link": return self.run(link_status)
        if u.path == "/api/vpn": return self.run(vpn_status)
        if u.path == "/api/split": return self.run(split_status)
        if u.path == "/api/jet": return self.run(jet_status)
        self.send(404, json.dumps({"error": "not found"}))
    def do_POST(self):
        if not self._auth_ok(): return
        u = urlparse(self.path); q = parse_qs(u.query); g = lambda k, d="": q.get(k, [d])[0]
        if u.path == "/api/start-test":
            return self.run(lambda: omr.omr_start_test({"duration": int(g("duration", "420"))}))
        if u.path == "/api/sched":
            return self.run(lambda: sched_set(g("name"), g("restart", "1") != "0"))
        if u.path == "/api/link":
            if g("action") == "cut": return self.run(lambda: link_cut(g("dev"), g("secs", "120")))
            if g("action") == "restore": return self.run(lambda: link_restore(g("dev")))
            return self.send(400, json.dumps({"ok": False, "error": "action must be cut or restore"}))
        if u.path == "/api/prio": return self.run(lambda: set_prio(g("mode")))
        if u.path == "/api/vpn": return self.run(lambda: vpn_set(g("name")))
        if u.path == "/api/split": return self.run(lambda: split_set(g("w", "0.5")))
        if u.path == "/api/loadtest":
            return self.run(lambda: loadtest(g("action", "start"), g("secs", "30"), g("mbps", "30")))
        self.send(404, json.dumps({"error": "not found"}))

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8799); ap.add_argument("--rpi", default=RPI)
    a = ap.parse_args(); RPI = a.rpi
    print(f"Digital Twin live: http://localhost:{a.port}  (Ctrl+C to stop)")
    ThreadingHTTPServer((a.host, a.port), H).serve_forever()
