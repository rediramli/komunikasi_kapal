#!/usr/bin/env python3
"""
Stage 3 orchestrator. Deploys the receiver to the VPS and the sender to the RPi,
opens the port, and sweeps the split weight w (the ML knob) to measure how
in-order video goodput and stall depend on how traffic is divided across the
12 ms and 90 ms SIMs. This is the experiment that exposes the reassembly penalty
the learned controller must minimise.

Run from the control host:  python3 run_stage3.py --weights 1.0 0.75 0.5 0.25 --dur 5

WARNING: saturates the cellular uplink (data) + stutters the camera stream.
Opens VPS port 5301 and closes it (+ kills proxies) in a finally block.
"""
import argparse, json, os, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
RPI = "root@100.102.109.59"
VPS = "root@168.144.105.155"
VPS_PORT = "65222"
VPS_PUB = "168.144.105.155"
PORT = 5301


def ssh(host, cmd, port=None, timeout=90, stdin=None):
    base = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]
    if port:
        base += ["-p", port]
    return subprocess.run(base + [host, cmd], input=stdin, capture_output=True,
                          text=True, timeout=timeout).stdout


def deploy():
    for host, port, name in ((VPS, VPS_PORT, "mpproxy_recv.py"), (RPI, None, "mpproxy_send.py")):
        src = open(os.path.join(HERE, name)).read()
        ssh(host, f"cat > /tmp/{name}", port=port, stdin=src)


def open_fw():
    ssh(VPS, f"nft list chain inet omr input 2>/dev/null | grep -q 'dport {PORT}' || "
             f"nft insert rule inet omr input tcp dport {PORT} accept comment \\\"stage3\\\"", port=VPS_PORT)


def close_fw():
    ssh(VPS, "while nft -a list chain inet omr input 2>/dev/null | grep -q stage3; do "
             "h=$(nft -a list chain inet omr input | awk '/stage3/{for(i=1;i<=NF;i++) "
             "if($i==\"handle\") print $(i+1); exit}'); nft delete rule inet omr input handle $h; done; echo ok", port=VPS_PORT)


# kill the process listening on a port, by pid from ss (no name matching -> never
# self-kills the shell the way `pkill -f mpproxy_recv` does, since this command's
# own argv contains that string).
_KILL_PORT = ("for p in $(ss -tlnp 2>/dev/null | grep ':%d ' | grep -oE 'pid=[0-9]+' "
              "| cut -d= -f2 | sort -u); do kill -9 $p 2>/dev/null; done")


def kill_procs():
    # build the name pattern from pieces so pkill -f can't match this very command
    ssh(VPS, 'P=mpproxy""_recv; pkill -9 -f "$P" 2>/dev/null; echo ok', port=VPS_PORT)
    ssh(RPI, 'P=mpproxy""_send; pkill -9 -f "$P" 2>/dev/null; echo ok')


def run_one(n1, n2, w, dur, bitrate, strict=False):
    conns = n1 + n2
    # free the port (kill any stale listener by pid), then start receiver detached
    ssh(VPS, (_KILL_PORT % PORT) + f"; sleep 0.3; "
             f"setsid python3 /tmp/mpproxy_recv.py --port {PORT} --conns {conns} "
             f">/tmp/recv.json 2>/tmp/recv.err < /dev/null & echo up", port=VPS_PORT, timeout=20)
    time.sleep(1.2)
    # run sender (blocks for ~dur)
    ssh(RPI, f"python3 /tmp/mpproxy_send.py --host {VPS_PUB} --port {PORT} "
             f"--n1 {n1} --n2 {n2} --w {w} --dur {dur} --bitrate {bitrate}"
             + (" --strict" if strict else ""),
        timeout=dur + 40)
    time.sleep(1.0)
    out = ssh(VPS, "cat /tmp/recv.json 2>/dev/null", port=VPS_PORT).strip()
    try:
        return json.loads(out)
    except Exception:
        return {"error": out[:120]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", type=float, nargs="+", default=[1.0, 0.75, 0.5, 0.25])
    ap.add_argument("--n1", type=int, default=4)
    ap.add_argument("--n2", type=int, default=4)
    ap.add_argument("--dur", type=float, default=5.0)
    ap.add_argument("--bitrate", type=float, default=0.0)
    ap.add_argument("--strict", action="store_true",
                    help="honour the split exactly (no work-stealing) -- shows w's true cost")
    a = ap.parse_args()

    deploy(); open_fw()
    try:
        print(f"{'w (Simba frac)':>16}{'in-order gp':>14}{'stall%':>9}{'reorder':>9}{'recv/deliv MB':>16}")
        for w in a.weights:
            r = run_one(a.n1, a.n2, w, a.dur, a.bitrate, a.strict)
            if "error" in r:
                print(f"{w:>16}   ERROR: {r['error']}"); continue
            print(f"{w:>16.2f}{r['inorder_goodput_mbps']:>11.1f} Mb"
                  f"{r['stall_frac']*100:>8.0f}%{r['reorder_depth_max']:>9}"
                  f"{r['received_mb']:>8.1f}/{r['delivered_mb']:<6.1f}")
    finally:
        kill_procs(); close_fw()
        print("cleaned up (fw closed, proxies killed).")


if __name__ == "__main__":
    main()
