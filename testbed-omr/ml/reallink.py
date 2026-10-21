"""
Real-testbed backend: run an action on the LIVE bonded link and measure goodput,
mirroring bond_env.step() so a policy trained offline can be validated / fine-
tuned online. This is the bridge from the calibrated model to reality.

IMPORTANT, read before running:
  * Every probe saturates the cellular uplink -> uses data quota (~N x dur MB)
    and briefly stutters the camera stream. Keep dur short and probes few.
  * ACTUATOR GAP: iperf3 -P N opens N streams but Glorytun distributes them
    itself -- it does NOT pin one stream per SIM with a weight w. So this probe
    validates only the N dimension (how many sub-streams) under glorytun's own
    splitting. Realising the *pinned, weighted* actuator the model assumes is
    the next build step (a sender that binds sub-streams to each WAN source IP,
    or per-SIM tunnels / an SRT|MPTCP multipath sender). Until then, treat
    reallink numbers as a partial, conservative check of the policy.

Usage:
  python3 reallink.py --probe 8          # one 6 s probe with 8 sub-streams
  python3 reallink.py --sweep 1 2 4 8 16 # characterise goodput vs N
"""

from __future__ import annotations
import argparse
import re
import subprocess

RPI = "root@100.102.109.59"       # RPi over tailscale
TUN_VPS = "10.255.254.1"          # VPS end of the Glorytun UDP tunnel
VPS = "root@168.144.105.155"
VPS_PORT = "65222"


def _ssh(host, cmd, port=None, timeout=40):
    base = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]
    if port:
        base += ["-p", port]
    return subprocess.run(base + [host, cmd], capture_output=True, text=True, timeout=timeout).stdout


def server_up() -> bool:
    _ssh(VPS, "pgrep -f 'iperf3 -s' >/dev/null || iperf3 -s -D", port=VPS_PORT)
    return "1" in _ssh(VPS, "ss -tlnp 2>/dev/null | grep -c :5201", port=VPS_PORT)


def server_stop():
    _ssh(VPS, "pkill -f 'iperf3 -s' 2>/dev/null; echo ok", port=VPS_PORT)


def observe() -> dict:
    """Per-SIM live state from the 1 Hz sampler CSV on the RPi (last row)."""
    row = _ssh(RPI, "tail -1 /tmp/omr_live.csv").strip()
    f = row.split(",")
    if len(f) < 12:
        return {}
    return {"simba_kbps": int(f[1]), "singtel_kbps": int(f[2]),
            "rtt_simba_ms": int(f[9]), "rtt_singtel_ms": int(f[10]),
            "rtt_tunnel_ms": int(f[11])}


def probe(n_substreams: int, dur: int = 6) -> float:
    """Run iperf3 with N sub-streams over the tunnel; return goodput Mbit/s."""
    out = _ssh(RPI, f"iperf3 -c {TUN_VPS} -P {n_substreams} -t {dur} -f m",
               timeout=dur + 30)
    # the [SUM] receiver line, or the single-stream receiver line for N=1
    m = re.findall(r"([\d.]+)\s+Mbits/sec\s+.*receiver", out)
    if not m:
        m = re.findall(r"([\d.]+)\s+Mbits/sec\s+receiver", out)
    return float(m[-1]) if m else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", type=int, help="run one probe with this many sub-streams")
    ap.add_argument("--sweep", type=int, nargs="+", help="probe each N in the list")
    ap.add_argument("--dur", type=int, default=6)
    a = ap.parse_args()

    if not server_up():
        print("could not start iperf3 server on the VPS"); return
    try:
        print("state before:", observe())
        targets = a.sweep or ([a.probe] if a.probe else [8])
        for n in targets:
            g = probe(n, a.dur)
            print(f"  N={n:<3d} -> {g:6.1f} Mbit/s")
    finally:
        server_stop()
        print("iperf3 server stopped.")


if __name__ == "__main__":
    main()
