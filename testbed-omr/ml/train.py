"""
Train the contextual bandit on the calibrated bonded-link model and evaluate it
against the baselines. Offline, instant, no cellular data.

Baselines:
  naive        -- glorytun single flow (the system today), the thing we beat
  fixed-best   -- the single best action ignoring link state (context-blind)
  learned      -- the LinUCB policy (reads the state, picks N & split)
  oracle       -- per-state best action (upper bound)

Run:  python3 train.py [--steps N] [--lam L] [--agent linucb|epsilon]
"""

from __future__ import annotations
import argparse
import numpy as np
from bond_env import BondEnv, ACTIONS, FEAT_DIM, features
from agent import LinUCB, EpsilonGreedy


def fixed_best_action(env, states):
    """Best single action averaged over states (context-blind baseline)."""
    means = []
    for a in range(len(ACTIONS)):
        means.append(np.mean([env.step(s, a)[0] for s in states]))
    return int(np.argmax(means))


def evaluate(env, agent, states, fixed_a):
    rows = {"naive": [], "fixed-best": [], "learned": [], "oracle": [],
            "sum": [], "lat_learned": []}
    for s in states:
        rows["sum"].append(s.cap1 + s.cap2)
        rows["naive"].append(env.naive(s))
        rows["fixed-best"].append(env.step(s, fixed_a)[1]["goodput"])
        a = agent.select(features(s), explore=False)
        _, info = env.step(s, a)
        rows["learned"].append(info["goodput"])
        rows["lat_learned"].append(info["latency"])
        _, orc = env.oracle(s)
        rows["oracle"].append(env.step(s, env.oracle(s)[0])[1]["goodput"])
    return {k: np.array(v) for k, v in rows.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steps", type=int, default=5000)
    ap.add_argument("--lam", type=float, default=0.0, help="latency weight (0=pure throughput)")
    ap.add_argument("--agent", choices=["linucb", "epsilon"], default="linucb")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--harsh", action="store_true",
                    help="volatile cellular: frequent, severe single-SIM degradation")
    a = ap.parse_args()

    dp, sev = (0.6, True) if a.harsh else (0.25, False)
    env = BondEnv(lam=a.lam, seed=a.seed, degrade_p=dp, severe=sev)
    agent = (LinUCB(len(ACTIONS), FEAT_DIM, alpha=0.5) if a.agent == "linucb"
             else EpsilonGreedy(len(ACTIONS), FEAT_DIM, eps=0.1))

    # ---- train ----
    regret = 0.0
    for t in range(1, a.steps + 1):
        s = env.sample_state()
        x = features(s)
        act = agent.select(x, explore=True)
        r, _ = env.step(s, act)
        agent.update(act, x, r)
        _, orc = env.oracle(s)
        regret += orc - r
        if t % max(1, a.steps // 5) == 0:
            print(f"  step {t:5d}/{a.steps}  avg regret/step = {regret/t:5.2f} Mbit/s")

    # ---- evaluate on a held-out set ----
    eval_env = BondEnv(lam=a.lam, seed=a.seed + 999, degrade_p=dp, severe=sev)
    states = [eval_env.sample_state() for _ in range(2000)]
    fixed_a = fixed_best_action(eval_env, states)
    R = evaluate(eval_env, agent, states, fixed_a)

    print(f"\n=== Evaluation on 2000 unseen link states (lam={a.lam}, agent={a.agent}) ===")
    print(f"{'policy':<12}{'mean goodput':>14}{'% of sum':>10}{'vs naive':>10}")
    naive = R["naive"].mean()
    sums = R["sum"].mean()
    for k in ("naive", "fixed-best", "learned", "oracle"):
        g = R[k].mean()
        print(f"{k:<12}{g:>11.1f} Mb{g/sums*100:>9.0f}%{(g/naive-1)*100:>+9.0f}%")
    fn = ACTIONS[fixed_a]
    print(f"\nfixed-best action (context-blind) = N={fn[0]}, w1={fn[1]}")
    print(f"learned mean latency = {R['lat_learned'].mean():.0f} ms")
    cap_learned = R["learned"].mean() / R["oracle"].mean() * 100
    print(f"learned captures {cap_learned:.0f}% of the oracle's goodput")

    # show the learned policy on a few representative states
    print("\n--- learned policy on sample states ---")
    print(f"{'cap1/cap2':>12}{'rtt1/rtt2':>12}{'loss':>10}{'-> action':>14}{'goodput':>10}")
    for s in states[:6]:
        act = agent.select(features(s), explore=False)
        n, w = ACTIONS[act]
        _, info = env.step(s, act)
        loss = f"{s.loss1:.2f}/{s.loss2:.2f}"
        print(f"{s.cap1:5.1f}/{s.cap2:4.1f}{s.rtt1:6.0f}/{s.rtt2:4.0f}{loss:>10}"
              f"   N={n:<2d} w={w:<4}{info['goodput']:>8.1f} Mb")


if __name__ == "__main__":
    main()
