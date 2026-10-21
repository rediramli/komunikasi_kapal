"""
Contextual-bandit agents for picking the bonding action from the live link state.

LinUCB is the default: one linear model per action, with an upper-confidence
bonus for exploration. It is fast, converges in a few hundred steps, needs no
GPU, and is interpretable (you can read each action's learned weights) -- a good
first policy before moving to a DQN. An epsilon-greedy baseline is included for
comparison.
"""

from __future__ import annotations
import numpy as np


class LinUCB:
    def __init__(self, n_actions: int, dim: int, alpha: float = 0.5, reward_scale: float = 30.0):
        self.n = n_actions
        self.d = dim
        self.alpha = alpha
        self.scale = reward_scale          # keep rewards ~O(1) for stable updates
        self.A = [np.eye(dim) for _ in range(n_actions)]
        self.b = [np.zeros(dim) for _ in range(n_actions)]
        self._Ainv = [np.eye(dim) for _ in range(n_actions)]

    def select(self, x: np.ndarray, explore: bool = True) -> int:
        best, best_p = 0, -1e18
        for a in range(self.n):
            Ainv = self._Ainv[a]
            theta = Ainv @ self.b[a]
            mean = float(theta @ x)
            bonus = self.alpha * np.sqrt(max(0.0, x @ Ainv @ x)) if explore else 0.0
            p = mean + bonus
            if p > best_p:
                best_p, best = p, a
        return best

    def update(self, a: int, x: np.ndarray, reward: float):
        r = reward / self.scale
        self.A[a] += np.outer(x, x)
        self.b[a] += r * x
        self._Ainv[a] = np.linalg.inv(self.A[a])


class EpsilonGreedy:
    def __init__(self, n_actions: int, dim: int, eps: float = 0.1, lr: float = 0.05,
                 reward_scale: float = 30.0):
        self.n = n_actions
        self.eps = eps
        self.lr = lr
        self.scale = reward_scale
        self.W = np.zeros((n_actions, dim))
        self.rng = np.random.default_rng(0)

    def select(self, x: np.ndarray, explore: bool = True) -> int:
        if explore and self.rng.random() < self.eps:
            return int(self.rng.integers(self.n))
        return int(np.argmax(self.W @ x))

    def update(self, a: int, x: np.ndarray, reward: float):
        r = reward / self.scale
        pred = self.W[a] @ x
        self.W[a] += self.lr * (r - pred) * x
