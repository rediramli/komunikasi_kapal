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
import argparse, subprocess, time, json
import numpy as np
from bond_env import ACTIONS, features
from link_model import LinkState
from controller import train_policy, decide
import reallink

RPI = "root@100.102.109.59"
CTL_FILE = "/tmp/mpproxy_w"
DECISION_FILE = "/tmp/jet_decision.json"   # the dashboard reads this to show how the AI decides

DEMO = [
    ("healthy",        LinkState(16, 17, 12, 90, 0, 0)),
    ("healthy",        LinkState(16, 17, 12, 90, 0, 0)),
    ("Singtel RTT250", LinkState(16, 17, 12, 250, 0, 0)),
    ("Singtel cap4",   LinkState(16, 4, 12, 90, 0, 0)),
    ("recovered",      LinkState(16, 17, 12, 90, 0, 0)),
    ("symmetric",      LinkState(16, 17, 30, 45, 0, 0)),
]


def push_w(w, ctl=CTL_FILE):
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", RPI,
                    f"echo {w:.3f} > {ctl}"], timeout=15)


def decision_snapshot(agent, st, n, w):
    """Expose HOW the LinUCB policy decided: observed state, the learned score of each
    split weight (exploit mean, max over N), and the chosen (N, w). Scores are
    normalised 0..1 only for display."""
    x = features(st)
    scores = [float((agent._Ainv[a] @ agent.b[a]) @ x) for a in range(agent.n)]
    byw = {}
    for a, (N, ww) in enumerate(ACTIONS):
        byw[ww] = max(byw.get(ww, -1e18), scores[a])
    ws = sorted(byw)
    vals = [byw[v] for v in ws]
    lo, hi = min(vals), max(vals)
    cand = [{"w": ws[i], "score": round((vals[i] - lo) / (hi - lo), 3) if hi > lo else 0.5,
             "chosen": abs(ws[i] - w) < 1e-6} for i in range(len(ws))]
    # reason is derived from the chosen w so it always matches the decision; the model
    # weighs goodput (capacity) against latency (RTT) per SIM.
    if w >= 0.6:
        lean = "more load to Simba"
    elif w <= 0.4:
        lean = "more load to Singtel"
    else:
        lean = "split close to balanced"
    driver = []
    if st.loss1 > 0.05 or st.loss2 > 0.05:
        driver.append("avoiding the packet-losing SIM")
    if abs(st.cap1 - st.cap2) > 3:
        driver.append("following the larger capacity")
    if abs(st.rtt1 - st.rtt2) > 40:
        driver.append("weighing the RTT difference")
    reason = lean + (" — " + ", ".join(driver) if driver else "")
    return {"ts": time.time(),
            "state": {"cap1": round(st.cap1, 1), "cap2": round(st.cap2, 1),
                      "rtt1": round(st.rtt1), "rtt2": round(st.rtt2),
                      "loss1": st.loss1, "loss2": st.loss2},
            "cand": cand, "chosen": {"N": n, "w": w}, "reason": reason}


def push_decision(d, path=DECISION_FILE):
    try:
        subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", RPI,
                        f"cat > {path}"], input=json.dumps(d).encode(), timeout=15)
    except Exception:
        pass


def _sim(cap, rtt, up, cut, rtt_ok):
    """Map one SIM's live readings to (cap, rtt, loss). A dead SIM (no ping reply
    rtt<0, state down, or manually cut) is reported as degraded so the policy
    shifts decisively to the healthy SIM instead of toward the dead one."""
    dead = (rtt is None) or (rtt < 0) or (up == 0) or (cut == 1)
    if dead:
        return 1.0, 300.0, 0.6          # tiny capacity, high RTT+loss -> avoid
    return cap, float(max(1, rtt)), 0.0


def observe(cap1, cap2):
    o = reallink.observe() or {}
    c1, r1, l1 = _sim(cap1, o.get("rtt_simba_ms"), o.get("wan1_up", 1), o.get("cut1", 0), 12)
    c2, r2, l2 = _sim(cap2, o.get("rtt_singtel_ms"), o.get("wan2_up", 1), o.get("cut2", 0), 90)
    return "live", LinkState(c1, c2, r1, r2, l1, l2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cycles", type=int, default=6)
    ap.add_argument("--period", type=float, default=3.0)
    ap.add_argument("--demo", action="store_true")
    ap.add_argument("--cap1", type=float, default=16.0)
    ap.add_argument("--cap2", type=float, default=17.0)
    ap.add_argument("--ctl", default=CTL_FILE, help="control file on the RPi (camera tunnel: /tmp/mptun_w)")
    a = ap.parse_args()

    print("edge controller: training policy ...")
    agent = train_policy()
    print(f"{'cycle':>6}{'state':>16}{'rtt1/rtt2':>12}{'-> w pushed':>14}")
    for i in range(a.cycles):
        # One flaky RPi SSH (observe/push over an unstable tunnel) must not kill the
        # controller: catch per-cycle errors and skip, so the loop keeps running.
        try:
            if a.demo:
                label, st = DEMO[i % len(DEMO)]
            else:
                label, st = observe(a.cap1, a.cap2)
            n, w = decide(agent, st)
            push_w(w, a.ctl)
            push_decision(decision_snapshot(agent, st, n, w))
            print(f"{i:>6}{label:>16}{st.rtt1:7.0f}/{st.rtt2:4.0f}{('N=%d w=%.2f' % (n, w)):>14}", flush=True)
        except Exception as e:
            print(f"{i:>6}  cycle error, skipping: {str(e)[:90]}", flush=True)
        time.sleep(a.period)
    print("done.")


if __name__ == "__main__":
    main()
