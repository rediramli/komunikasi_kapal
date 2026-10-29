#!/usr/bin/env python3
"""
Win-table: compare bonding controllers on the SAME states with the SAME calibrated
goodput model (link_model.evaluate). This answers the reviewer/advisor question
"do we need the AI, or would a rule do?" by putting LinUCB head-to-head with:
  - naive    : glorytun single-flow (the system before any controller)
  - static   : fixed balanced split (N=8, w=0.5), no adaptation
  - round_robin : cycles the split weight, adapts but ignores context
  - rule     : hand-tuned threshold rules on RTT/loss  <-- the key baseline
  - linucb   : our trained contextual bandit
  - ORACLE   : best action per state (upper bound, for reference)

Metrics per state-set (mean over states):
  goodput (Mbit/s, higher better) · %oracle (how close to best possible) ·
  stall%  (fraction of states with goodput below a video-floor) · latency (ms).

State sets:
  A  PSA real trace (Simba = recorded RUT241, Singtel healthy) -- harsh, clear-cut
  B  static scenarios S0..S6 mapped to states
  C  "ambiguous" states: BOTH SIMs partially degraded -> optimal split is a
     proportion, not a 0/0.5/1 switch. This is where context-learning should pay.

Run:  python3 wintable.py            (prints the table + writes wintable.json)
"""
import csv, json, sys
import numpy as np
from link_model import LinkState, evaluate, naive_baseline, CAP1_NOM, CAP2_NOM
from bond_env import ACTIONS, BondEnv
from controller import train_policy, decide

STALL_FLOOR = 4.0    # Mbit/s video floor: goodput below this = a stalled sample
LAM = 0.05
TRACE = "/home/redi/fssd-proj-2-3/testbed-omr/ml/captures/d10-psa-trace.csv"

# ---------------- controllers: state -> (N, w) ----------------
def c_static(s, t):      return (8, 0.5)
def c_rr(s, t):          return (8, (0.0,0.25,0.5,0.75,1.0)[t % 5])
def c_rule(s, t):
    r1,r2,l1,l2 = s.rtt1, s.rtt2, s.loss1, s.loss2
    dead1 = l1 >= 0.5 or r1 >= 250
    dead2 = l2 >= 0.5 or r2 >= 250
    if dead1 and not dead2:   w = 0.0
    elif dead2 and not dead1: w = 1.0
    elif dead1 and dead2:     w = 0.5
    elif l1 > 0.05 or r1 > 150: w = 0.25     # Simba weak -> lean Singtel
    elif l2 > 0.05 or r2 > 150: w = 0.75     # Singtel weak -> lean Simba
    else:                       w = 0.5
    return (8, w)
AGENT = None
def c_linucb(s, t):
    return decide(AGENT, s)

# naive handled specially (its own goodput model)
CONTROLLERS = [("naive", None), ("static", c_static), ("round_robin", c_rr),
               ("rule", c_rule), ("linucb", c_linucb)]

def action_idx(n, w):
    # snap to nearest action in ACTIONS
    best, bd = 0, 1e9
    for i,(an,aw) in enumerate(ACTIONS):
        d = abs(an-n)/16.0 + abs(aw-w)
        if d < bd: bd, best = d, i
    return best

def score_controller(fn, states):
    gp=[]; eff=[]; stalls=0; lat=[]; rew=[]
    for t,s in enumerate(states):
        # oracle on the ACTUAL objective (reward = goodput - LAM*latency)
        rs = [evaluate(s, *ACTIONS[a], LAM)[0] for a in range(len(ACTIONS))]
        o_rew = max(rs)
        if fn is None:
            g = naive_baseline(s); l = (s.rtt1+s.rtt2)/2; r = g - LAM*l
        else:
            n,w = fn(s,t); r,info = evaluate(s, n, w, LAM)
            g = info["goodput"]; l = info["latency"]
        gp.append(g); lat.append(l); rew.append(r)
        eff.append(r/o_rew if o_rew>1e-6 else 1.0)
        if g < STALL_FLOOR: stalls += 1
    return {"reward": float(np.mean(rew)), "goodput": float(np.mean(gp)),
            "pct_oracle": float(np.mean(eff)*100),
            "stall_pct": 100.0*stalls/len(states), "latency": float(np.mean(lat))}

# ---------------- state sets ----------------
def states_trace():
    out=[]
    for r in csv.DictReader(open(TRACE)):
        rtt=float(r["rtt_ms"]); loss=float(r["loss_pct"])/100.0; up=int(r["up"])
        if up==0 or rtt<0:                 # demoted -> dead Simba
            s = LinkState(cap1=0.4, cap2=CAP2_NOM, rtt1=400, rtt2=90, loss1=0.95, loss2=0.0)
        else:
            cong = max(0.05, min(1.0, 80.0/max(rtt,80.0)))   # high RTT -> less usable cap
            s = LinkState(cap1=CAP1_NOM*cong*(1-loss), cap2=CAP2_NOM,
                          rtt1=rtt, rtt2=90, loss1=loss, loss2=0.0)
        out.append(s)
    return out

def states_scenarios():
    # S0..S6 mapped to (rtt1, loss1, cap1 from netem rate); Singtel healthy
    S = {
      "S0": (12, 0.0, CAP1_NOM), "S1": (30, 0.005, CAP1_NOM*0.95),
      "S2": (80, 0.02, 5.0), "S3": (150, 0.05, 2.0),
      "S4": (300, 0.10, 1.0), "S6": (600, 0.01, 5.0),
    }
    return [LinkState(cap1=c, cap2=CAP2_NOM, rtt1=r, rtt2=90, loss1=l, loss2=0.0)
            for (r,l,c) in S.values()], list(S.keys())

def states_ambiguous(n=400, seed=1):
    # BOTH SIMs partially degraded with different caps -> optimal split is a
    # proportion; a coarse threshold rule should lose ground to a learned policy.
    rng = np.random.default_rng(seed); out=[]
    for _ in range(n):
        cap1 = rng.uniform(3, 14); cap2 = rng.uniform(3, 16)
        rtt1 = rng.uniform(20, 180); rtt2 = rng.uniform(40, 220)
        loss1 = rng.uniform(0, 0.12); loss2 = rng.uniform(0, 0.12)
        out.append(LinkState(cap1,cap2,rtt1,rtt2,loss1,loss2))
    return out

def main():
    global AGENT
    print("training LinUCB policy ...", file=sys.stderr)
    AGENT = train_policy()
    sets = {"A. PSA real trace": states_trace()[0] if False else states_trace(),
            "B. Static S0-S6": states_scenarios()[0],
            "C. Ambiguous (both degraded)": states_ambiguous()}
    results = {}
    for setname, states in sets.items():
        results[setname] = {name: score_controller(fn, states) for name,fn in CONTROLLERS}
    # print
    for setname, res in results.items():
        print(f"\n=== {setname}  ({len(sets[setname])} states) ===")
        print(f"{'controller':<12}{'reward':>9}{'%oracle':>9}{'goodput':>9}{'lat ms':>8}{'stall%':>8}")
        best = max(res.values(), key=lambda m: m['reward'])['reward']
        for name,_ in CONTROLLERS:
            m=res[name]; star = "  <-- best" if abs(m['reward']-best)<1e-9 else ""
            print(f"{name:<12}{m['reward']:>9.1f}{m['pct_oracle']:>9.1f}{m['goodput']:>9.1f}{m['latency']:>8.0f}{m['stall_pct']:>8.1f}{star}")
    json.dump(results, open("/home/redi/fssd-proj-2-3/testbed-omr/ml/wintable.json","w"), indent=2)
    print("\nwrote wintable.json", file=sys.stderr)

if __name__ == "__main__":
    main()
