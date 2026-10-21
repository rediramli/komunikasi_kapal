"""
Gym-like environment over the calibrated bonded-link model.

Each step: a random link STATE is drawn (cellular conditions drift; a SIM may
degrade), the agent picks an ACTION (N sub-streams, split weight), and gets a
REWARD = effective goodput - lam * latency. Because the optimal action moves
with the state, a context-blind policy cannot win -- the agent has to learn the
mapping state -> best (N, w). The same interface is implemented against the real
testbed in reallink.py for validation.
"""

from __future__ import annotations
import numpy as np
from link_model import LinkState, evaluate, naive_baseline

# Action space: N parallel pinned sub-streams x split weight to Simba (path 1).
N_CHOICES = (1, 2, 4, 8, 16)
W_CHOICES = (0.0, 0.25, 0.5, 0.75, 1.0)
ACTIONS = [(n, w) for n in N_CHOICES for w in W_CHOICES]


def features(state: LinkState) -> np.ndarray:
    """Normalised context vector for a linear agent (+ bias term)."""
    c1, c2, r1, r2, l1, l2 = state.as_obs()
    return np.array([
        c1 / 25.0, c2 / 25.0,          # caps (Mbit/s)
        r1 / 150.0, r2 / 150.0,        # RTTs (ms)
        l1 * 5.0, l2 * 5.0,            # loss fractions
        1.0,                           # bias
    ], dtype=float)


FEAT_DIM = 7


class BondEnv:
    def __init__(self, lam: float = 0.0, seed: int = 0,
                 degrade_p: float = 0.25, severe: bool = False):
        self.lam = lam
        self.rng = np.random.default_rng(seed)
        self.degrade_p = degrade_p     # how often a SIM degrades
        self.severe = severe           # harsh cellular: deeper drops + high RTT spikes

    def sample_state(self) -> LinkState:
        rng = self.rng
        cap1 = rng.uniform(6.0, 18.0)       # Simba  capacity drifts
        cap2 = rng.uniform(8.0, 22.0)       # Singtel capacity drifts
        rtt1 = rng.uniform(8.0, 45.0)       # Simba  usually low RTT
        rtt2 = rng.uniform(40.0, 130.0)     # Singtel usually high RTT
        loss1 = loss2 = 0.0
        if rng.random() < self.degrade_p:   # one SIM degrades
            cap_mul = (0.08, 0.3) if self.severe else (0.4, 0.8)
            loss_rng = (0.08, 0.35) if self.severe else (0.03, 0.18)
            if rng.random() < 0.5:
                loss1 = rng.uniform(*loss_rng); cap1 *= rng.uniform(*cap_mul)
                if self.severe:
                    rtt1 = rng.uniform(80.0, 300.0)   # Simba RTT spikes too
            else:
                loss2 = rng.uniform(*loss_rng); cap2 *= rng.uniform(*cap_mul)
                if self.severe:
                    rtt2 = rng.uniform(120.0, 350.0)
        return LinkState(cap1, cap2, rtt1, rtt2, loss1, loss2)

    def step(self, state: LinkState, action_idx: int):
        n, w = ACTIONS[action_idx]
        return evaluate(state, n, w, self.lam)       # (reward, info)

    def oracle(self, state: LinkState):
        """Best possible action for this state (upper bound)."""
        rewards = [self.step(state, a)[0] for a in range(len(ACTIONS))]
        a = int(np.argmax(rewards))
        return a, rewards[a]

    def naive(self, state: LinkState) -> float:
        """glorytun single-flow reference goodput (the system today)."""
        return naive_baseline(state)
