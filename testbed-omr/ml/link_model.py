"""
Calibrated model of the 2-SIM bonded uplink (RPi -> VPS over Glorytun UDP).

This is a *training* model, not the real link. It is calibrated against the
iperf3 measurements on the live testbed (21 Oct 2026) so an agent can be trained
offline (unlimited, free, no cellular data) and later validated on the real link
via reallink.py. Recalibrate as more measurements arrive.

Measured anchors (uplink RPi -> VPS, 8 s):
    Simba   (wan1, RTT ~12 ms) alone, raw  : 14.5 Mbit/s   -> cap1
    Singtel (wan2, RTT ~90 ms) alone, raw  : 18.1 Mbit/s   -> cap2
    bonded, 1 flow through tunnel (naive)  : 14.0 Mbit/s   (reordering collapse)
    bonded, 8 flows through tunnel (-P 8)  : 22.6 Mbit/s   (69% of the 32.6 sum)
    theoretical sum                        : 32.6 Mbit/s

Mechanism the model captures (what the measurements proved):
  * One TCP stream fills ONE path to its cap (raw single-SIM hit 14.5 / 18.1).
  * The collapse is REORDERING: when the bytes of one logical application stream
    (the video) are reassembled IN ORDER across a 12 ms and a 90 ms path, the
    receiver stalls waiting for the laggard -> effective goodput drops. More
    pinned sub-streams = bigger reassembly buffer = less stall; an even split
    across very asymmetric RTTs is the worst case.

STAGE 2 REAL VALIDATION (actuator.py, 21 Oct 2026) -- important refinement:
  Pinned sub-streams (bound per-WAN, bypassing glorytun) reach the FULL sum for
  INDEPENDENT streams: 1 Simba + 1 Singtel pinned measured 32.6 Mbit/s (= the
  sum), 2+2 -> 35, 4+4 -> 34. So the raw capacity is fully accessible and the
  reassembly penalty below applies ONLY to a single IN-ORDER stream (the video),
  not to independent throughput. The iperf3-pinned number is therefore the
  *ceiling*; real video goodput = ceiling x reassembly_factor, and optimising
  that factor (buffer, split, when to drop the slow SIM) is the Stage 3 ML job.

Actuator (chosen): N parallel sub-streams, each pinned to one path, split by
weight w1 (fraction of sub-streams on path 1 / Simba). The agent picks (N, w1)
from the live per-SIM state.
"""

from __future__ import annotations
from dataclasses import dataclass
import math

# ---- measured anchors (defaults for the "nominal" link state) ----
CAP1_NOM, RTT1_NOM = 14.5, 12.0     # Simba  (wan1)
CAP2_NOM, RTT2_NOM = 18.1, 90.0     # Singtel (wan2)
NAIVE_BONDED = 14.0                 # glorytun single-flow reference

# ---- calibrated constants ----
_F1 = 0.90           # fraction of a path one pinned stream fills; fill(n)=1-(1-F1)^n
_KNEE = 10.0         # per-path sub-streams before self-congestion
_OVERSHOOT = 0.010   # extra loss per sub-stream above the knee
_REORDER_ALPHA = 0.52   # strength of the in-order reassembly penalty
_REORDER_RTT = 100.0    # ms; RTT skew is measured relative to this
_REORDER_NSCALE = 4.0   # more sub-streams shrink the penalty (buffer effect)
_REORDER_MS = 420.0  # max reassembly delay added to LATENCY (not goodput). Stage 3
                     # real data: a balanced split MAXIMISES goodput (w=0.5 -> 32.5)
                     # while raising reorder buffering -> the penalty is latency, not
                     # throughput. (Earlier the model wrongly docked goodput at balance.)
_QUEUE_MS = 55.0     # added latency at full path utilisation (queueing)
_OVERHEAD_PER_SUB = 0.22  # Mbit/s of goodput lost per sub-stream (ACKs, headers,
                          # CPU, retransmits). Makes "more streams" not free, so
                          # the optimal N depends on how much capacity is there.


def _fill(n: int) -> float:
    if n <= 0:
        return 0.0
    return 1.0 - (1.0 - _F1) ** n


@dataclass
class LinkState:
    """One snapshot of the two SIMs -- what the agent observes."""
    cap1: float = CAP1_NOM   # Mbit/s, Simba
    cap2: float = CAP2_NOM   # Mbit/s, Singtel
    rtt1: float = RTT1_NOM   # ms
    rtt2: float = RTT2_NOM   # ms
    loss1: float = 0.0       # base loss fraction, path 1
    loss2: float = 0.0       # base loss fraction, path 2

    def as_obs(self):
        return (self.cap1, self.cap2, self.rtt1, self.rtt2, self.loss1, self.loss2)


def _raw_path(cap, base_loss, n_sub):
    if n_sub <= 0:
        return 0.0
    overshoot = max(0.0, n_sub - _KNEE) * _OVERSHOOT
    eff = max(0.0, 1.0 - base_loss - overshoot)
    return cap * _fill(n_sub) * eff


def _split(n: int, w1: float):
    n = max(1, int(n))
    w1 = min(1.0, max(0.0, float(w1)))
    n1 = int(round(n * w1))
    n1 = min(n, max(0, n1))
    n2 = n - n1
    return n1, n2


def evaluate(state: LinkState, n: int, w1: float, lam: float = 0.0):
    """
    Apply an action (N sub-streams, split weight w1 to Simba) to a link state.

    Returns (reward, info) where
        reward = effective_goodput_mbps - lam * latency_cost
        info   = dict with goodput, latency, n1, n2, per-path raw.
    lam>0 makes the objective latency-aware (penalises leaning on the 90 ms SIM).
    """
    n1, n2 = _split(n, w1)
    raw1 = _raw_path(state.cap1, state.loss1, n1)
    raw2 = _raw_path(state.cap2, state.loss2, n2)
    raw = raw1 + raw2
    if raw <= 1e-6:
        return 0.0, {"goodput": 0.0, "latency": max(state.rtt1, state.rtt2),
                     "n1": n1, "n2": n2, "raw1": raw1, "raw2": raw2}

    f1, f2 = raw1 / raw, raw2 / raw
    skew = abs(state.rtt1 - state.rtt2) / _REORDER_RTT
    # goodput peaks at a balanced split (both SIMs used); overhead per sub-stream.
    goodput = max(0.0, raw - (n1 + n2) * _OVERHEAD_PER_SUB)
    # the reassembly cost is LATENCY: worst at an even split (4*f1*f2 -> 1) across a
    # big RTT skew; a larger reorder buffer (more sub-streams) softens it.
    reorder_ms = _REORDER_MS * (4.0 * f1 * f2) * skew / (1.0 + n / _REORDER_NSCALE)
    lat1 = state.rtt1 + _QUEUE_MS * _fill(n1)
    lat2 = state.rtt2 + _QUEUE_MS * _fill(n2)
    latency = (raw1 * lat1 + raw2 * lat2) / raw + reorder_ms
    reward = goodput - lam * latency
    return reward, {"goodput": goodput, "latency": latency,
                    "n1": n1, "n2": n2, "raw1": raw1, "raw2": raw2}


def naive_baseline(state: LinkState) -> float:
    """glorytun single-flow reference, scaled with the available sum."""
    nom_sum = CAP1_NOM + CAP2_NOM
    return NAIVE_BONDED * ((state.cap1 + state.cap2) / nom_sum)


if __name__ == "__main__":
    s = LinkState()
    print(f"nominal state: {s.as_obs()}")
    print(f"theoretical sum        : {s.cap1 + s.cap2:.1f} Mbit/s")
    print(f"naive glorytun baseline: {naive_baseline(s):.1f} Mbit/s  (measured 14.0)")
    for n in (1, 2, 4, 8, 16):
        best = max(((n, w, evaluate(s, n, w / 4.0)) for w in range(5)),
                   key=lambda r: r[2][1]["goodput"])
        g = best[2][1]
        print(f"  pinned best @ N={n:<2d}: goodput {g['goodput']:5.1f} Mbit/s  "
              f"lat {g['latency']:4.0f} ms  n1={g['n1']} n2={g['n2']}")
