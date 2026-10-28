#!/usr/bin/env python3
"""omr-twin: server MCP lokal (stdio) untuk halaman 'Digital Twin MPTCP'.

Berjalan di REDLAB, dipanggil oleh aplikasi Claude desktop. Mengambil data live dari
RPi OMR lewat SSH (pakai SSH key yang dipasang oleh setup-ssh-key.sh).

Tools:
  omr_live(since)     baris sampel sejak epoch `since`, info uji terakhir, usia permintaan SSH, dan estimasi selisih jam (read-only)
  omr_start_test(dur) mulai failover-test.sh mode otomatis di RPi (aksi)
Tanpa dependensi selain Python 3 dan ssh.
"""
import json, os, subprocess, sys, time

HOST = os.environ.get("OMR_RPI", "root@100.102.109.59")
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
       "-o", "ControlMaster=auto", "-o", "ControlPath=/tmp/omr-twin-%r@%h:%p",
       "-o", "ControlPersist=120", HOST]

SAMPLER = r'''#!/bin/sh
# omr-live.sh - sampler 1 Hz untuk Digital Twin (dipasang otomatis oleh omr-twin)
F=/tmp/omr_live.csv; echo $$ > /tmp/omr_live.pid
txb() { cat /sys/class/net/$1/statistics/tx_bytes 2>/dev/null || echo 0; }
VPS=${VPS:-168.144.105.155}
# RTT (ms, rounded) to the VPS via one WAN; -1 when unreachable within 1s.
prif() { ping -c1 -W1 -I "$1" "$VPS" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | awk 'NR==1{printf "%d",($1+0.5);f=1} END{if(!f)print -1}'; }
prdef() { ping -c1 -W1 "$VPS" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | awk 'NR==1{printf "%d",($1+0.5);f=1} END{if(!f)print -1}'; }
IP1=$(uci -q get network.wan1.ipaddr); IP2=$(uci -q get network.wan2.ipaddr)
a=$(txb wan1); b=$(txb wan2); n=0
while :; do
  sleep 1
  c=$(txb wan1); d=$(txb wan2)
  x=$(( (c-a)*8/1000 )); y=$(( (d-b)*8/1000 )); a=$c; b=$d
  s1=$(uci -q get openmptcprouter.wan1.state); s2=$(uci -q get openmptcprouter.wan2.state)
  ov=$(ss -tan 2>/dev/null | grep ESTAB | grep ':65301')
  o1=$(echo "$ov" | grep -c "$IP1[%:]"); o2=$(echo "$ov" | grep -c "$IP2[%:]")
  t=$(nft list table inet fotest 2>/dev/null); k1=0; k2=0
  echo "$t" | grep -q pre_wan1 && k1=1; echo "$t" | grep -q pre_wan2 && k2=1
  r1=$(prif wan1); r2=$(prif wan2); rt=$(prdef)
  echo "$(date +%s),$x,$y,$([ "$s1" = up ] && echo 1 || echo 0),$([ "$s2" = up ] && echo 1 || echo 0),$o1,$o2,$k1,$k2,$r1,$r2,$rt" >> $F
  n=$((n+1))
  if [ $n -ge 300 ]; then tail -900 $F > $F.tmp && mv $F.tmp $F; n=0; fi
  # runs continuously (no idle self-stop) so the dashboard never freezes; a single guarded
  # instance is enforced by the pid-file check in run_sampler() / rc.local at boot.
done
'''

LIVE_CMD = r'''
S=%(since)d
[ -f /root/omr-live.sh ] || { echo NEED_INSTALL; exit 0; }
date +%%s > /tmp/omr_live.ping
if [ -s /tmp/omr_live.pid ] &&
   kill -0 "$(cat /tmp/omr_live.pid)" 2>/dev/null &&
   tr '\000' ' ' < "/proc/$(cat /tmp/omr_live.pid)/cmdline" 2>/dev/null | grep -Fq '/root/omr-live.sh'; then
  :
else
  nohup sh /root/omr-live.sh </dev/null >/dev/null 2>&1 & sleep 2
fi
echo "NOW $(date +%%s)"
awk -F, -v s=$S '$1>s' /tmp/omr_live.csv 2>/dev/null | tail -300 | sed 's/^/R /'
D=$(ls -dt /root/fotest_*/ 2>/dev/null | head -1)
if [ -n "$D" ]; then
  echo "TDIR $D"; echo "TSTART $(cat $D/start 2>/dev/null)"; [ -f $D/done ] && echo "TDONE 1"
  sed 's/^/TPLAN /' $D/plan.txt 2>/dev/null || true
  sed 's/^/TMARK /' $D/marks.csv 2>/dev/null
fi
'''

def ssh(cmd, stdin=None, timeout=20):
    p = subprocess.run(SSH + [cmd], input=stdin, capture_output=True, text=True, timeout=timeout)
    if p.returncode != 0 and not p.stdout:
        raise RuntimeError((p.stderr or "ssh gagal").strip()[-400:])
    return p.stdout

def omr_live(args):
    since = int(args.get("since") or 0)
    started = time.time()
    out = ssh(LIVE_CMD % {"since": since})
    if out.startswith("NEED_INSTALL"):
        ssh("cat > /root/omr-live.sh && chmod +x /root/omr-live.sh", stdin=SAMPLER)
        out = ssh(LIVE_CMD % {"since": since})
    finished = time.time()
    res = {"now": None, "rows": [], "test": None}
    test = {"dir": None, "start": None, "done": False, "plan": [], "marks": []}
    for line in out.splitlines():
        tag, _, rest = line.partition(" ")
        if tag == "NOW": res["now"] = int(rest)
        elif tag == "R":
            try: res["rows"].append([int(v) for v in rest.split(",")])
            except ValueError: pass
        elif tag == "TDIR": test["dir"] = rest.strip()
        elif tag == "TSTART" and rest.strip(): test["start"] = int(rest)
        elif tag == "TDONE": test["done"] = True
        elif tag == "TPLAN" and "|" in rest:
            o, lab = rest.split("|", 1); test["plan"].append({"t": int(o), "label": lab})
        elif tag == "TMARK":
            parts = rest.split(",")
            if parts and parts[0].isdigit(): test["marks"].append({"epoch": int(parts[0]), "what": parts[-1]})
    if test["dir"]: res["test"] = test
    res["columns"] = ["epoch", "simba_kbps", "singtel_kbps", "simba_up", "singtel_up",
                      "openvpn_sf_simba", "openvpn_sf_singtel", "simba_cut_auto", "singtel_cut_auto",
                      "rtt_simba_ms", "rtt_singtel_ms", "rtt_tunnel_ms"]
    res["ssh_ms"] = round((finished - started) * 1000)
    if res["now"] is not None:
        res["clock_skew_s"] = round(res["now"] - (started + finished) / 2, 1)
    return res

def omr_start_test(args):
    dur = int(args.get("duration") or 420)
    if not 60 <= dur <= 1800: raise ValueError("duration harus 60-1800 detik")
    out = ssh("[ -f /root/failover-test.sh ] || { echo 'failover-test.sh tidak ada di /root'; exit 0; }; "
              "D=$(ls -dt /root/fotest_*/ 2>/dev/null | head -1); "
              "if [ -n \"$D\" ] && [ ! -f \"$D/done\" ]; then echo 'Tes lain masih berjalan:' $D; exit 0; fi; "
              f"nohup sh /root/failover-test.sh {dur} auto </dev/null >/root/fotest_last_console.txt 2>&1 & "
              "sleep 6; tr '\\r' '\\n' < /root/fotest_last_console.txt | grep -v '^ *\\[' | head -20")
    return {"started": "Jadwal:" in out, "console": out.strip()}

TOOLS = [
    {"name": "omr_live", "description": "Sampel live 1 Hz dari RPi OMR (upload per link, status OMR, subflow tunnel OpenVPN, link yang diputus tes otomatis) sejak epoch `since`, plus info tes failover terakhir.",
     "inputSchema": {"type": "object", "properties": {"since": {"type": "integer", "description": "epoch detik; 0 = semua yang tersimpan (maks 300 baris)"}}},
     "annotations": {"readOnlyHint": True}},
    {"name": "omr_start_test", "description": "Mulai tes failover otomatis (failover-test.sh ... auto) di RPi OMR.",
     "inputSchema": {"type": "object", "properties": {"duration": {"type": "integer", "description": "durasi detik, default 420"}}},
     "annotations": {"readOnlyHint": False, "destructiveHint": False}},
]
IMPL = {"omr_live": omr_live, "omr_start_test": omr_start_test}

def reply(i, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": i}
    if error: msg["error"] = error
    else: msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n"); sys.stdout.flush()

for raw in sys.stdin:
    raw = raw.strip()
    if not raw: continue
    try: req = json.loads(raw)
    except ValueError: continue
    mid, method, params = req.get("id"), req.get("method"), req.get("params") or {}
    if mid is None: continue  # notifications
    if method == "initialize":
        reply(mid, {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {}}, "serverInfo": {"name": "omr-twin", "version": "1.0"}})
    elif method == "tools/list":
        reply(mid, {"tools": TOOLS})
    elif method == "tools/call":
        name = params.get("name"); args = params.get("arguments") or {}
        try:
            data = IMPL[name](args)
            reply(mid, {"content": [{"type": "text", "text": json.dumps(data)}], "structuredContent": data})
        except KeyError:
            reply(mid, error={"code": -32601, "message": f"tool tidak dikenal: {name}"})
        except Exception as e:
            reply(mid, {"content": [{"type": "text", "text": f"Gagal: {e}"}], "isError": True})
    elif method == "ping":
        reply(mid, {})
    else:
        reply(mid, error={"code": -32601, "message": "method not found"})
