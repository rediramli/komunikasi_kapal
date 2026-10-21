#!/usr/bin/env python3
"""
Stage 3b: close the loop. Train the Stage 1 policy, read the LIVE per-SIM state,
let the policy choose the split w, and drive the real Stage 3 proxy with it --
then show the policy's decisions adapt as the state changes.

Honest note on observation: the 1 Hz sampler gives real per-SIM RTT live, but not
capacity (it only sees the small camera flow) or loss. So the controller uses
live RTTs + a capacity estimate (--cap1/--cap2, seeded from the last measurement;
a real deployment would refresh it from recent achieved throughput or a probe).

Usage:
  python3 controller.py --run            # decide from live state, run the proxy
  python3 controller.py                  # decision table only (offline, no data)
"""
import argparse
import numpy as np
from bond_env import BondEnv, ACTIONS, features
from agent import LinUCB
from link_model import LinkState
import reallink
import run_stage3


# Latency-aware objective: goodput matters, but leaning on the 90 ms SIM (or a
# degraded one) costs latency. This makes the split w genuinely state-dependent
# (the throughput-only objective's optimum is ~w=0.5 everywhere -- see README).
LAM = 0.05


def train_policy(steps=12000, seed=0, lam=LAM):
    env = BondEnv(seed=seed, lam=lam, degrade_p=0.6, severe=True)   # volatile links
    agent = LinUCB(len(ACTIONS), 7, alpha=0.6)
    for _ in range(steps):
        s = env.sample_state(); x = features(s)
        a = agent.select(x); r, _ = env.step(s, a); agent.update(a, x, r)
    return agent


def decide(agent, state: LinkState):
    a = agent.select(features(state), explore=False)
    return ACTIONS[a]              # (N, w)


def observe_live(cap1, cap2):
    """Live per-SIM state: real RTTs from the sampler + capacity estimate."""
    o = reallink.observe()
    rtt1 = o.get("rtt_simba_ms", 12) if o else 12
    rtt2 = o.get("rtt_singtel_ms", 90) if o else 90
    return LinkState(cap1=cap1, cap2=cap2, rtt1=float(max(1, rtt1)),
                     rtt2=float(max(1, rtt2)), loss1=0.0, loss2=0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cap1", type=float, default=16.0, help="Simba capacity estimate (Mbit/s)")
    ap.add_argument("--cap2", type=float, default=17.0, help="Singtel capacity estimate (Mbit/s)")
    ap.add_argument("--run", action="store_true", help="run the real proxy with the chosen split")
    ap.add_argument("--dur", type=float, default=5.0)
    a = ap.parse_args()

    print("training policy on volatile-link model ...")
    agent = train_policy()

    state = observe_live(a.cap1, a.cap2)
    n, w = decide(agent, state)
    print(f"\nLIVE state: cap≈{state.cap1:.0f}/{state.cap2:.0f} Mb  "
          f"rtt={state.rtt1:.0f}/{state.rtt2:.0f} ms")
    print(f"policy decision: N={n}, w(Simba fraction)={w}")

    if a.run:
        print("\nrunning the real proxy with the policy's split (and w=0.5 baseline) ...")
        run_stage3.deploy(); run_stage3.open_fw()
        try:
            for label, ww in (("policy", w), ("fixed-0.5", 0.5)):
                r = run_stage3.run_one(4, 4, ww, a.dur, 0.0, strict=True)
                g = r.get("inorder_goodput_mbps", "?")
                print(f"  {label:<10} w={ww:<4} -> in-order goodput {g} Mb  "
                      f"(reorder {r.get('reorder_depth_max','?')})")
        finally:
            run_stage3.kill_procs(); run_stage3.close_fw()
            print("cleaned up.")

    # show adaptation: the chosen split changes with the state
    print("\n--- policy decisions across states (adaptation) ---")
    print(f"{'cap1/cap2':>12}{'rtt1/rtt2':>12}{'loss2':>8}{'-> N, w':>12}")
    demo = [
        LinkState(16, 17, 12, 90, 0, 0),      # nominal
        LinkState(16, 17, 12, 250, 0, 0),     # Singtel RTT spikes
        LinkState(16, 4, 12, 90, 0, 0.0),     # Singtel capacity collapses
        LinkState(16, 17, 12, 90, 0, 0.25),   # Singtel lossy
        LinkState(5, 17, 40, 60, 0, 0),       # Simba weak, RTTs closer
    ]
    for s in demo:
        n, w = decide(agent, s)
        print(f"{s.cap1:5.0f}/{s.cap2:4.0f}{s.rtt1:7.0f}/{s.rtt2:4.0f}{s.loss2:8.2f}"
              f"     N={n:<2d} w={w}")


if __name__ == "__main__":
    main()
