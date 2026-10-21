"""
Stage 2: pinned sub-stream actuator (real link).

Realises an action (N sub-streams, split weight w to Simba) by SOURCE-BINDING
sub-streams to each WAN, which OMR policy-routes out that specific SIM --
bypassing the Glorytun tunnel, so there is no cross-path reordering. n1 streams
go out Simba (wan1), n2 out Singtel (wan2), concurrently, and their goodput is
summed. This is the real counterpart of link_model.evaluate(): the action the
learned policy chooses actually gets applied and measured.

Two iperf3 servers (ports 5201 = Simba, 5202 = Singtel) let the two pinned
bundles run truly concurrently (one iperf3 server serialises tests).

WARNING: each probe saturates the cellular uplink -> data quota (~N x dur MB)
and briefly stutters the camera stream. Keep dur short and probes few. Always
call close_fw()/stop_servers() when done (main() does this in a finally block).

Note: iperf3 streams are independent, so this measures the RAW aggregate a
pinned splitter can reach (the ceiling). A real in-order video stream still pays
a reassembly penalty across the RTT skew -- that is the Stage 3 problem.
"""

from __future__ import annotations
import argparse
import json
import subprocess

RPI = "root@100.102.109.59"
VPS = "root@168.144.105.155"
VPS_PORT = "65222"
VPS_PUB = "168.144.105.155"
WAN1_IP = "192.168.1.100"    # Simba  (wan1, ~12 ms)
WAN2_IP = "192.168.2.100"    # Singtel (wan2, ~90 ms)
P1, P2 = 5201, 5202


def _ssh(host, cmd, port=None, timeout=60):
    base = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]
    if port:
        base += ["-p", port]
    return subprocess.run(base + [host, cmd], capture_output=True, text=True, timeout=timeout).stdout


def start_servers():
    _ssh(VPS, f"for p in {P1} {P2}; do pgrep -f \"iperf3 -s -p $p\" >/dev/null || "
              f"iperf3 -s -p $p -D; done", port=VPS_PORT)


def stop_servers():
    _ssh(VPS, f"pkill -f 'iperf3 -s' 2>/dev/null; echo ok", port=VPS_PORT)


def open_fw():
    _ssh(VPS, f"for p in {P1} {P2}; do nft list chain inet omr input 2>/dev/null | "
              f"grep -q \"dport $p\" || nft insert rule inet omr input tcp dport $p accept "
              f"comment \\\"iperf-stage2\\\"; done", port=VPS_PORT)


def close_fw():
    _ssh(VPS, "while nft -a list chain inet omr input 2>/dev/null | grep -q iperf-stage2; do "
              "h=$(nft -a list chain inet omr input | awk '/iperf-stage2/{for(i=1;i<=NF;i++) "
              "if($i==\"handle\") print $(i+1); exit}'); nft delete rule inet omr input handle $h; "
              "done; echo closed", port=VPS_PORT)


def _split(n, w):
    n = max(1, int(n)); w = min(1.0, max(0.0, float(w)))
    n1 = min(n, max(0, int(round(n * w)))); n2 = n - n1
    if 0.0 < w < 1.0:
        n1 = max(1, n1); n2 = max(1, n - n1)
    return n1, n2


def _goodput_json(txt):
    try:
        return json.loads(txt)["end"]["sum_received"]["bits_per_second"] / 1e6
    except Exception:
        return 0.0


def apply_action(n, w, dur=5):
    """Run pinned action (N, w) on the real link; return measured goodput (Mbit/s)."""
    n1, n2 = _split(n, w)
    parts = []
    if n1 > 0:
        parts.append(f"iperf3 -c {VPS_PUB} -p {P1} -B {WAN1_IP} -P {n1} -t {dur} -J >/tmp/s1.json 2>/dev/null &")
    if n2 > 0:
        parts.append(f"iperf3 -c {VPS_PUB} -p {P2} -B {WAN2_IP} -P {n2} -t {dur} -J >/tmp/s2.json 2>/dev/null &")
    script = " ".join(parts) + " wait; echo '==S1=='; cat /tmp/s1.json 2>/dev/null; echo '==S2=='; cat /tmp/s2.json 2>/dev/null"
    out = _ssh(RPI, script, timeout=dur + 40)
    s1 = out.split("==S1==", 1)[-1].split("==S2==", 1)[0]
    s2 = out.split("==S2==", 1)[-1]
    g1 = _goodput_json(s1) if n1 > 0 else 0.0
    g2 = _goodput_json(s2) if n2 > 0 else 0.0
    return {"n": n, "w": w, "n1": n1, "n2": n2, "g1": g1, "g2": g2, "goodput": g1 + g2}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dur", type=int, default=5)
    ap.add_argument("--actions", default="1:1.0,1:0.0,2:0.5,4:0.5,8:0.5",
                    help="comma list of N:w to probe")
    a = ap.parse_args()
    actions = [(int(x.split(":")[0]), float(x.split(":")[1])) for x in a.actions.split(",")]

    open_fw(); start_servers()
    try:
        print(f"{'action':>12}{'n1/n2':>8}{'Simba':>9}{'Singtel':>9}{'TOTAL':>9}")
        for n, w in actions:
            r = apply_action(n, w, a.dur)
            print(f"  N={r['n']:<2d} w={r['w']:<4}{str(r['n1'])+'/'+str(r['n2']):>8}"
                  f"{r['g1']:>8.1f}{r['g2']:>9.1f}{r['goodput']:>9.1f} Mb")
    finally:
        close_fw(); stop_servers()
        print("firewall closed, servers stopped.")


if __name__ == "__main__":
    main()
