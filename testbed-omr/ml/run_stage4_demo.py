#!/usr/bin/env python3
"""
Stage 4 full-loop demo (run from the control host). Brings up the proxy
(receiver on VPS, sender on RPi reading a live control file) and runs the edge
controller ON THE JETSON, which observes and pushes the split w to the RPi. Shows
the sender applying the Jetson's decisions mid-stream.

python3 run_stage4_demo.py            # Jetson decides from a demo state sequence
python3 run_stage4_demo.py --live     # Jetson decides from real live telemetry
"""
import argparse, os, subprocess, time
import run_stage3 as R

JETSON = "jetson@10.42.0.3"
HERE = os.path.dirname(os.path.abspath(__file__))


def jssh(cmd, timeout=60):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", JETSON, cmd],
                          capture_output=True, text=True, timeout=timeout).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true", help="Jetson uses real telemetry (else demo states)")
    ap.add_argument("--dur", type=int, default=20)
    a = ap.parse_args()

    R.deploy()
    subprocess.run(f"tar czf - -C {HERE} . | ssh -o BatchMode=yes {JETSON} 'tar xzf - -C ~/bonding-ml'",
                   shell=True, check=False)
    R.ssh(R.RPI, "echo 0.5 > /tmp/mpproxy_w")
    R.open_fw()
    try:
        R.ssh(R.VPS, (R._KILL_PORT % R.PORT) + f"; sleep 0.3; setsid python3 /tmp/mpproxy_recv.py "
              f"--port {R.PORT} --conns 8 >/tmp/recv.json 2>/tmp/recv.err </dev/null & echo up",
              port=R.VPS_PORT, timeout=20)
        time.sleep(1.2)
        R.ssh(R.RPI, f"setsid python3 /tmp/mpproxy_send.py --host {R.VPS_PUB} --port {R.PORT} "
              f"--n1 4 --n2 4 --w 0.5 --dur {a.dur} --bitrate 0 --strict --ctl /tmp/mpproxy_w "
              f">/tmp/send.out 2>/tmp/send.err </dev/null & echo started", timeout=15)
        time.sleep(1.5)
        mode = "" if a.live else "--demo"
        print(f"=== edge controller running ON THE JETSON ({'live' if a.live else 'demo'} states) ===")
        print(jssh(f"cd ~/bonding-ml && python3 edge_control.py {mode} --cycles 6 --period 3", timeout=45))
        time.sleep(3)
        print("=== sender's control log on the RPi (w changes it actually applied) ===")
        print(R.ssh(R.RPI, "cat /tmp/send.err 2>/dev/null").strip() or "(none)")
        print("=== receiver metrics (VPS) ===")
        print(R.ssh(R.VPS, "cat /tmp/recv.json 2>/dev/null", port=R.VPS_PORT).strip() or "(none)")
    finally:
        R.kill_procs(); R.close_fw()
        print("cleaned up.")


if __name__ == "__main__":
    main()
