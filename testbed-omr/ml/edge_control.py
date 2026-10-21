#!/usr/bin/env python3
"""
Stage 4 edge controller -- runs on the Jetson (the brain).

Loop: observe the live per-SIM state from the RPi -> the policy picks the split w
-> push w to the proxy sender's control file on the RPi (over SSH). The sender
polls that file and changes its split mid-stream. This closes the loop: Jetson
decides, RPi actuates.

Modes:
  (default)  read real live telemetry from the RPi each cycle
  --demo     cycle through representative states so the pushed w visibly changes
             even on a stable link (for showing the control channel works)

Usage (on the Jetson):
  python3 edge_control.py --cycles 6 --period 3
  python3 edge_control.py --demo --cycles 8 --period 2
"""
import argparse, subprocess, time
from bond_env import ACTIONS, features
from link_model import LinkState
from controller import train_policy, decide
import reallink

RPI = "root@100.102.109.59"
CTL_FILE = "/tmp/mpproxy_w"

DEMO = [
    ("healthy",        LinkState(16, 17, 12, 90, 0, 0)),
    ("healthy",        LinkState(16, 17, 12, 90, 0, 0)),
    ("Singtel RTT250", LinkState(16, 17, 12, 250, 0, 0)),
    ("Singtel cap4",   LinkState(16, 4, 12, 90, 0, 0)),
    ("recovered",      LinkState(16, 17, 12, 90, 0, 0)),
    ("symmetric",      LinkState(16, 17, 30, 45, 0, 0)),
]


def push_w(w):
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", RPI,
                    f"echo {w:.3f} > {CTL_FILE}"], timeout=15)


def observe(cap1, cap2):
    o = reallink.observe()
    rtt1 = o.get("rtt_simba_ms", 12) if o else 12
    rtt2 = o.get("rtt_singtel_ms", 90) if o else 90
    return "live", LinkState(cap1, cap2, float(max(1, rtt1)), float(max(1, rtt2)), 0, 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cycles", type=int, default=6)
    ap.add_argument("--period", type=float, default=3.0)
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--cap1", type=float, default=16.0)
    ap.add_argument("--cap2", type=float, default=17.0)
    a = ap.parse_args()

    print("edge controller: training policy ...")
    agent = train_policy()
    print(f"{'cycle':>6}{'state':>16}{'rtt1/rtt2':>12}{'-> w pushed':>14}")
    for i in range(a.cycles):
        if a.demo:
            label, st = DEMO[i % len(DEMO)]
        else:
            label, st = observe(a.cap1, a.cap2)
        n, w = decide(agent, st)
        push_w(w)
        print(f"{i:>6}{label:>16}{st.rtt1:7.0f}/{st.rtt2:4.0f}{('N=%d w=%.2f' % (n, w)):>14}")
        time.sleep(a.period)
    print("done.")


if __name__ == "__main__":
    main()
