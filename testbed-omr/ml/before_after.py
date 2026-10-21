#!/usr/bin/env python3
"""
Before/after on the real link, in one comparable metric: what ONE video stream
gets today vs with the Jetson-driven pinned multipath proxy.

  BEFORE : a single flow over the Glorytun UDP tunnel (the deployed system).
  AFTER  : the Jetson reads the live state, picks the split w, and the pinned
           proxy carries the stream with it -> in-order goodput.

Run from the control host:  python3 before_after.py [--dur 6]
Uses cellular data and briefly disturbs the camera stream; cleans up after.
"""
import argparse, subprocess
import reallink
import run_stage3 as R

JETSON = "jetson@10.42.0.3"


def jssh(cmd, t=60):
    return subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", JETSON, cmd],
                          capture_output=True, text=True, timeout=t).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dur", type=int, default=6)
    a = ap.parse_args()

    # ---- BEFORE: glorytun single flow over the tunnel ----
    print("measuring BEFORE (glorytun single flow over the tunnel) ...")
    R.ssh(R.VPS, "iperf3 -s -D 2>/dev/null; sleep 0.4; echo up", port=R.VPS_PORT)  # start server directly
    before = reallink.probe(1, dur=a.dur)
    R.ssh(R.VPS, 'P=iperf""3; pkill -f "$P -s" 2>/dev/null; echo ok', port=R.VPS_PORT)  # stop (self-match-proof)

    # ---- Jetson decides w from the live state ----
    print("asking the Jetson for its split decision from live telemetry ...")
    dec = jssh("cd ~/bonding-ml && python3 -c \""
               "from controller import train_policy, decide; "
               "from edge_control import observe; "
               "ag=train_policy(); _,st=observe(16,17); n,w=decide(ag,st); "
               "print(n, w, round(st.rtt1), round(st.rtt2))\"", t=60).strip().split()
    n, w, rtt1, rtt2 = int(dec[0]), float(dec[1]), dec[2], dec[3]

    # ---- AFTER: pinned proxy with the Jetson's split ----
    print(f"measuring AFTER (Jetson chose N={n}, w={w} for rtt {rtt1}/{rtt2} ms) ...")
    R.deploy(); R.open_fw()
    try:
        after = R.run_one(4, 4, w, a.dur, 0.0, strict=True)
    finally:
        R.kill_procs(); R.close_fw()

    ag = after.get("inorder_goodput_mbps", 0)
    print("\n================= BEFORE / AFTER (one video stream) =================")
    print(f"  BEFORE  glorytun single flow            : {before:5.1f} Mbit/s")
    print(f"  AFTER   Jetson-driven pinned proxy (w={w}) : {ag:5.1f} Mbit/s")
    if before > 0:
        print(f"  improvement                             : {ag/before:.2f}x  (+{(ag/before-1)*100:.0f}%)")
    print("====================================================================")


if __name__ == "__main__":
    main()
