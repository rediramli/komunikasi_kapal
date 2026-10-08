# FSSD Proj 2-3 — Ad-hoc Radio Access Technologies for Robust Maritime Connectivity

> **This README is written for AI agents.** Read it fully before making changes
> to any component. It contains hard-won lessons that will save you from
> repeating mistakes already made and documented.

**Institution:** Singapore Institute of Technology (SIT), FSSD Programme
**Researcher:** Redi Ramli
**Supervisor:** Prof. Neelakantam Venkatarayalu (Prof. Venkat)
**Industry partner:** Jason Marine Group (funds the project)
**Started:** 2024 · **Deployed aboard vessel:** 24 Sep 2026

---

## 1. What this project is

A research platform for **multi-link maritime connectivity** — combining
cellular (5G + 4G) and satellite (Starlink, planned) links into a single
resilient gateway aboard a harbor vessel operating in Singapore waters.

The project has **three workstreams** that share infrastructure:

| # | Workstream | What it does | Where the code lives |
|---|---|---|---|
| 1 | **Maritime Gateway** | MPTCP bonding, 3-tier traffic classification, failover, telemetry collection | `gateway/` (RPi) + `server/` |
| 2 | **M-AIRMap Heatmap** | Deep-learning maritime RF coverage prediction (U-Net) | `heatmap/` (Jetson) + `server/` |
| 3 | **PCI Prediction** | Cell handover prediction using RF + position features | `pci-prediction/` |

All three feed into a single research question: **how should a gateway allocate
safety-critical traffic across unreliable, heterogeneous radio links at sea?**

The vessel is **PSA Agility**, a harbor cargo craft operating exclusively
between **Pulau Brani, Pasir Panjang, and Tuas** terminals in Singapore. It
never leaves Singapore waters.

---

## 2. Architecture — four machines

```
┌─────────────────────────────────────────────────────┐
│                   ABOARD VESSEL                      │
│                                                      │
│  ┌──────────────┐  eth0   ┌──────────────────────┐  │
│  │  RUTM30      │◄───────►│                      │  │
│  │  Singtel 5G  │         │   Raspberry Pi 5     │  │
│  │  (primary)   │         │   Debian 13 Trixie   │  │
│  └──────────────┘         │   kernel 6.12        │  │
│                           │                      │  │
│  ┌──────────────┐  eth1   │   MPTCP gateway      │  │
│  │  RUT241      │◄───────►│   WiFi AP            │  │
│  │  Simba 4G    │         │   nftables tiers     │  │
│  │  (backup)    │         │   telemetry collector │  │
│  └──────────────┘         └──────────┬───────────┘  │
│                              wlan0 ▼  │ tailscale    │
│  ┌──────────────┐         ┌──────────┴───┐          │
│  │ AIS receiver │◄───────►│ Ship devices │          │
│  │ (Ethan/JM)   │  WiFi   │              │          │
│  │ 192.168.50.38│         └──────────────┘          │
│  └──────────────┘                                    │
└──────────────────────────────┬───────────────────────┘
                               │ MPTCP over dual cellular
                               ▼
                    ┌──────────────────────┐
                    │  DigitalOcean Server  │
                    │  157.230.47.109       │
                    │                       │
                    │  Flask API :5000      │
                    │  Grafana   :3000      │
                    │  SQLite DB            │
                    │  M-AIRMap viewer      │
                    └──────────────────────┘
                               ▲
                               │ push_prediction.py
                    ┌──────────────────────┐
                    │  Jetson Orin Nano     │
                    │  JetPack 5.1.3       │
                    │  CUDA 11.4           │
                    │  PyTorch 2.1.0       │
                    │  ~/m-airmap/          │
                    └──────────────────────┘
```

### IP addresses

| Device | Interface | IP | Notes |
|---|---|---|---|
| **Server** | — | `157.230.47.109` | SSH: `root@`, Grafana: `:3000` (admin/Singapore2026=), API: `:5000` |
| **RPi** | eth0 | `192.168.1.144` | → RUTM30/Singtel, gw `192.168.1.1`, metric 100 |
| **RPi** | eth1 | `192.168.2.164` | → RUT241/Simba, gw `192.168.2.1`, metric 200 |
| **RPi** | wlan0 | `192.168.50.1` | WiFi AP (SSID: SIT-Maritime-Gateway) |
| **RPi** | tailscale0 | `100.119.32.0` | Remote management |
| **RUTM30** | LAN | `192.168.1.1` | Singtel 5G router, admin via HTTPS |
| **RUT241** | LAN | `192.168.2.1` | Simba 4G router, admin via HTTPS |
| **AIS receiver** | WiFi | `192.168.50.38` | Ethan's device, forwards to his server (plain TCP, not MPTCP) |
| **Jetson** | — | `10.42.0.164` | Lab network, not on vessel |

> ⚠️ **`192.168.50.41` is fake.** It appears in `mock_server.py` as a BirdDog
> camera placeholder. The camera is not installed yet.

> ⚠️ **Grafana password is in plaintext** in `add_tier_panels.py`. If that file
> has been shared, the credential should be rotated.

### SSH access

```bash
# Server
ssh root@157.230.47.109

# RPi (via Tailscale)
ssh fctlab@100.119.32.0

# RUT241 admin (tunnel through RPi)
ssh -N -L 9191:192.168.2.1:443 fctlab@raspberrypi
# then https://localhost:9191 (accept cert warning)

# RUTM30 admin (tunnel through RPi)
ssh -N -L 9192:192.168.1.1:443 fctlab@raspberrypi
# then https://localhost:9192
```

---

## 3. Repo structure

```
fssd-proj-2-3/
├── README.md                  ← you are here
├── .gitignore
├── .env.example               ← template for credentials
│
├── gateway/                   ← Raspberry Pi scripts & config
│   ├── README.md
│   ├── scripts/               ← Python scripts (collectors, senders)
│   ├── systemd/               ← .service and .timer unit files
│   ├── network/               ← MPTCP setup, nftables rules, WiFi AP
│   └── diagnostics/           ← check_rut241.sh and similar
│
├── heatmap/                   ← M-AIRMap (Jetson Orin Nano)
│   ├── README.md
│   ├── config.yaml            ← single source of truth for parameters
│   ├── core/                  ← digital_twin.py orchestrator
│   ├── modules/               ← geography, infrastructure, environment,
│   │                            propagation, validation
│   ├── model/                 ← U-Net, training, calibration
│   └── push_prediction.py
│
├── pci-prediction/            ← PCI boundary & handover prediction
│   ├── README.md
│   └── ...                    ← to be organized
│
├── server/                    ← DigitalOcean server code
│   ├── README.md
│   ├── app.py                 ← Flask API
│   ├── static/                ← M-AIRMap viewer HTML
│   ├── grafana/               ← dashboard JSON exports
│   └── schema.sql             ← DB schema reference
│
└── docs/
    ├── learnings.md           ← mistakes made and lessons learned
    ├── ip-reference.md        ← network addresses and access
    └── architecture.md        ← detailed architecture notes
```

---

## 4. Workstream 1 — Maritime Gateway

### What it does

The RPi acts as a **MPTCP-bonded gateway** for all devices aboard the vessel.
Traffic is classified into three tiers using nftables:

| Tier | Traffic | Scheduling | Port |
|---|---|---|---|
| **1 — Safety** | AIS, sensors, telemetry | Redundant (both paths) | 5000 |
| **2 — Operational** | Navigation video | Lowest-RTT path | 6060 |
| **3 — Administrative** | Bulk, crew, updates | Default (best-effort) | all other |

### Critical understanding: MPTCP bonding scope

**MPTCP bonding only works end-to-end.** Both the sender AND receiver must speak
MPTCP. Currently:

- ✅ **Gateway ↔ FSSD Server**: bonded (server runs `mptcpize`)
- ❌ **AIS receiver → Ethan's server**: NOT bonded (his server is plain TCP)

This means **94% of forwarded traffic (Tier 1 AIS, 2.71 GB) is NOT bonded.**
Only Tier 2 telemetry (~91.7 MB) to the FSSD server uses MPTCP subflows.

To bond third-party traffic, a **shore-side MPTCP aggregator** is needed: the
gateway terminates connections locally, carries them over bonded MPTCP transport
to a shore endpoint, which forwards as TCP to the destination. This component
does not exist yet.

### Measured performance (verified 25 Sep – 7 Oct 2026)

| Metric | Value | Source |
|---|---|---|
| eth0 throughput (Singtel 5G) | 30.2 Mbps | iperf3 |
| eth1 throughput (Simba 4G) | 2.67 Mbps | iperf3 |
| AIS 24h average | 42.8 kbps (4.8–111.7 range) | nft counters, 29–30 Sep |
| AIS packet rate | 67.3 pkt/s | 2823 samples |
| AIS daily volume | 440.8 MB/day | calculated |
| Tier 1 cumulative | 2.71 GB (28.7M packets) | nft counters |
| Tier 2 cumulative | 91.7 MB (675K packets) | nft counters |
| Forward total | 2.87 GB | nft counters |

### Key scripts on the RPi

| Script | Purpose | Systemd unit |
|---|---|---|
| `platform_stats.py` | Collects link stats every ~30s (up/down, RTT, loss, bytes) | `maritime-stats.timer` |
| `drivetest_sender.py` | Combines GPS + SSH signal reads from both routers every 5s | `maritime-drivetest.service` |
| `setup_mptcp.sh` | MPTCP endpoints, policy routing tables 1 & 2 | `mptcp-limits.service` |
| `setup_wifi_ap.sh` | WiFi AP on wlan0 | `maritime-wifi-ap.service` |
| `mqtt_bridge.py` | Bridge MQTT → tier-appropriate ports | manual |
| `check_rut241.sh` | Diagnostic: interface, routing, ping, MPTCP, services | manual |

### Policy routing (DO NOT CHANGE without reading this)

```
pref 5208: from 192.168.2.164 lookup 2    ← eth1/RUT241 traffic
pref 5209: from 192.168.1.144 lookup 1    ← eth0/RUTM30 traffic
```

**Tables are 1 and 2, NOT 100/200.** `ip rule show` does NOT print interface
names — it prints `lookup <table-number>`. An earlier debugging session
incorrectly concluded routing was missing because `grep eth1` found nothing.
The routing was present the entire time.

### Timer-driven systemd units (DO NOT assume they're dead)

`maritime-stats.service` is a **oneshot** unit triggered by `maritime-stats.timer`
every ~30 seconds. `systemctl is-active maritime-stats.service` returns
**`inactive`** between runs. This is normal. Check the timer, not the service:

```bash
systemctl list-timers maritime-stats.timer
```

---

## 5. Workstream 2 — M-AIRMap Heatmap

### What it does

Predicts cellular coverage (RSRP) over Singapore's southern waters using a
U-Net trained on synthetic 3-ray propagation data, calibrated against real
scanner measurements.

### Research gap (the novel contribution)

All existing DL radio-map methods (AIRMap, RadioUNet, DeepREM, PMNet) target
**urban** environments. Maritime propagation literature produces point-level
predictions, never pixel-level spatial radio maps. **Nobody has combined the
two.** This project does.

### Current result

```
MAE:           7.28 dB
Median error:  5.9%
Test points:   159,320
Calibration:   RSRP_cal = 4.592 × RSRP_pred + 127.20
Platform:      Jetson Orin Nano GPU, ~4.5 min training
```

### Known issues (MUST READ before presenting results)

1. **Synthetic BS placed anywhere, including open sea** — should be
   coastline-constrained using `geography["coastline_mask"]`
2. **Train/inference BS count mismatch** — training sees 1 BS per sample,
   inference uses 30. Fix: vary BS count per sample
3. **BS locations are heuristic** — strongest-RSRP clustering, not survey data.
   "Strongest = nearest" is weak at sea. `config.yaml → infrastructure.source:
   "official"` is wired for when real data arrives
4. **Environment module is a stub** — static 28°C/80% humidity/calm. Matters
   physically (evaporation duct height)
5. **Sionna RT not implemented** — OptiX needs x86_64, Jetson is aarch64
6. **Cosmetic bug in `train.py`** — second calibration call logs identity fit;
   first line is the valid one

### Design principle

Every module is **swappable**. `ModuleState.is_placeholder` propagates honesty
to the web UI. **Do not break this.** It's why the system can be shown to
regulators and industry partners without overclaiming.

### How to run

```bash
# On the Jetson
cd ~/m-airmap
nano config.yaml                          # edit parameters

# If propagation params changed, delete cache first!
rm data/synthetic/dataset.npz

python3 -m model.train                    # retrain
python3 push_prediction.py                # push to server
# reload http://157.230.47.109:5000/viewer
```

---

## 6. Workstream 3 — PCI Prediction

### What it does

Predicts which Physical Cell ID (PCI) a vessel will be served by, based on
position and RF history. Originally framed as handover prediction for maritime
autonomous surface vessels.

### Key findings (from scanner analysis)

- Non-boundary accuracy: 97–99.6%
- **Boundary (transition zone) accuracy drops to 71–80%** — cell handover
  zones are where prediction matters most and is hardest
- Sliding window (n=1, using `prev_pci`) recovers accuracy to 99.4%
- Cross-campaign generalization drops to 49% without history features (only
  21% PCI overlap between campaigns)
- **SHAP: `prev_pci` is the #1 feature** (0.049), followed by longitude
  (0.030), confirming the memory effect in cell selection

### New insight from gateway operations (Oct 2026)

**RF-only prediction is insufficient for maritime.** The RUT241 PLMN rejection
event (7 Oct 2026) showed:

- Modem camped on Malaysian cell (MCC 502, U Mobile, Band 28 / 788 MHz) while
  in **Singapore waters** near Tuas
- RSRP and SINR were measurable (−106 / −13 dB) — the cell appeared viable
  by RF metrics alone
- Registration was rejected: "EPS services not allowed in this PLMN"
- **A model predicting handover from RSRP/SINR would have predicted this cell
  as usable.** It was not.

Implication: **PLMN identity, registration state, and reject cause must be
first-class features**, not just RF measurements. This is a maritime-specific
contribution — land-based models rarely encounter cross-border cell selection.

### Status

Early stage. Files not yet organized. Will be developed further incorporating
gateway operational learnings.

---

## 7. Server

### Database: SQLite at `/var/lib/grafana/maritime.db`

```sql
-- Main tables
measurements    -- RF telemetry (RSRP, SINR, PCI, cell_id, band, lat, lon)
                -- device_id: 'RUT241', 'RUTM30', 'DRIVETEST'
link_stats      -- per-interface up/down, RTT, loss, byte counters
tier_traffic    -- per-tier byte/packet counts
predicted_maps  -- M-AIRMap predictions (grid, quality report, MAE)
```

### API endpoints (Flask on :5000)

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/predicted_map` | POST | Jetson pushes prediction |
| `/api/predicted_map` | GET | Viewer fetches prediction |
| `/latest` | GET | Last 20 live measurements |
| `/viewer` | GET | M-AIRMap web viewer |
| `/data`, `/status`, `/history`, `/raw`, `/throughput` | GET | Telemetry |

### Grafana dashboards (`:3000`)

- `maritime-v3` — main operational dashboard (Bondix-style per-channel)
- `jason-marine-demo-v2` — demo for industry partner

**Critical:** `timeColumns: ["time","ts"]` must be set in the SQLite datasource
configuration (UID `afpb2eygfssu8a`), or time-series panels will not render.

---

## 8. Learnings — mistakes already made, do not repeat

### 8.1 AT command measurement: QCSQ vs QENG

**Problem:** `AT+QCSQ` returns cached values. Six consecutive reads returned
exactly −99 dBm while real conditions varied. This was misdiagnosed as a link
failure three times before being identified.

**Solution:** Always use `AT+QENG="servingcell"` for RSRP. It reads from the
modem's measurement layer on each call. The 2–3 dB offset between commands is
the same order as the propagation effects being studied.

**Rule:** Record which AT command produced every RSRP value in the dataset.

### 8.2 PLMN camping on foreign cells in domestic waters

**Event:** 7 Oct 2026. RUT241 (Simba SIM) camped on MCC 502 / MNC 18
(U Mobile, Malaysia) on Band 28 (788 MHz) while the vessel was operating
between Singapore PSA terminals.

**Root cause:** Band 28 (700 MHz) propagates far over water. Malaysian cells
in Johor are only a few km across the strait from Tuas terminal. Both countries
use Band 28 — no frequency-based separation. The modem selected the foreign
cell by signal strength, then was rejected: "EPS services not allowed in this
PLMN."

**Key insight:** The vessel never left Singapore waters. A domestic SIM can
lose service without crossing any border — the cell selection algorithm picks
based on signal strength, not geography.

**Mitigation:** PLMN lock (force MCC 525 only) via router admin, or preferred
operator list. Not yet implemented.

### 8.3 Policy routing tables are 1 and 2, not 100/200

`ip rule show` prints `lookup 2`, not `lookup 200`, and does not print
interface names. Searching for `grep eth1` or `grep 200` will find nothing.
The rules are at preferences 5208 and 5209. They have been present since
deployment and were never missing.

### 8.4 Timer-driven oneshot services look dead but are alive

`systemctl is-active` on a oneshot between timer firings returns `inactive`.
This led to a false conclusion that "nothing is collecting telemetry." Check
`systemctl list-timers` instead.

### 8.5 MPTCP bonding requires both endpoints

Bonding is end-to-end. If the destination server does not speak MPTCP, traffic
falls back to single-path TCP. AIS traffic to Ethan's server (the dominant
flow, 94% of forwarded data) is NOT bonded. Do not claim bonded throughput
for this traffic.

### 8.6 Fabricated GPS coordinates in router telemetry

106,622 rows in `measurements` contain fabricated coordinates from the Teltonika
routers' Data to Server JSON template, which includes `lat` and `lon` fields
by default. These are NOT from the GPS (which is dead). The coordinates have
been nulled but the fix (removing lat/lon from the JSON template on both
routers) is not yet applied.

### 8.7 iperf3 bonding test requires mptcpize on BOTH sides

```bash
# On server
mptcpize run iperf3 -s

# On RPi
mptcpize run iperf3 -c 157.230.47.109
```

`iperf3 -s -D` (daemonized) may silently fail. Run in foreground.
`speed.cloudflare.com` does not speak MPTCP — it cannot test bonding.

### 8.8 leaflet.heat does not work for dense grids

Feeding a 89×66 grid (5,874 overlapping points) into `leaflet.heat` produces
one solid blob with no spatial variation. Use canvas pixel painting + bilinear
upscale + `L.imageOverlay` instead.

### 8.9 Simba coverage is thinner than other Singapore operators

Simba is the newest and smallest of four Singapore mobile operators. Its
coastal and maritime coverage is thinner. Two Singapore SIMs (Singtel +
Simba) provide operator diversity but not true coverage diversity for
maritime use. Starlink would provide a genuinely different failure mode.

### 8.10 RUT241 mob1s1a1 autostart

The interface `mob1s1a1` has been observed with `autostart: false` and
`mwan3.mob1s1a1.enabled='0'`. When this happens, the modem does not
automatically reconnect after a data session drop. Check and re-enable via
the router admin panel: Network → Interfaces → mob1s1a1.

---

## 9. Open items (as of 8 Oct 2026)

### Gateway
- [ ] Remove `lat`/`lon` from Data to Server JSON template on both routers
- [ ] Clean up redundant table 200 ip rules on RPi
- [ ] Implement PLMN lock on RUT241 (force MCC 525)
- [ ] Fix `mob1s1a1` autostart on RUT241
- [ ] Relocate GPS antenna (reports healthy but sees no satellites — physical mounting issue)
- [ ] Run proper MPTCP bonding test with `mptcpize` on both ends
- [ ] Design shore-side MPTCP aggregator for third-party traffic
- [ ] Investigate `maritime-tier.service` persistence across reboots

### Heatmap
- [ ] Fix 7.1: constrain synthetic BS placement to coastline
- [ ] Fix 7.2: vary BS count per training sample (1–30)
- [ ] Wire `environment.py` to real weather API
- [ ] Comparison study: RBF vs Kriging vs U-Net on same held-out split
- [ ] Leave-one-route-out validation

### PCI Prediction
- [ ] Organize files into repo structure
- [ ] Incorporate PLMN state as a feature (not just RF)
- [ ] Cross-campaign validation with scanner data
- [ ] Integration with gateway telemetry for live testing

---

## 10. How to contribute (for AI agents)

1. **Read this entire README** before making changes.
2. **Read `docs/learnings.md`** — it exists to prevent you from re-discovering
   known issues.
3. **Do not overclaim.** If a module uses placeholder data, say so. If bonding
   doesn't cover a traffic flow, say so. The project's credibility depends on
   honest reporting.
4. **Record your mistakes.** When you debug something and find the cause was
   different from your hypothesis, add it to `docs/learnings.md`. Future agents
   will thank you.
5. **Discuss before creating documents.** The project owner prefers to discuss
   approach before any document or code is produced.
6. **Data to Server JSON template:** lat/lon fields on Teltonika routers
   produce fake coordinates. Do not use them for location. GPS is the only
   valid position source, and it is currently broken.

---

## 11. Related references

- AIRMap (IEEE TWC 2025) — the paper being adapted for maritime
- Lee et al., RadioEngineering 2014 — three-ray model validated in Singapore waters
- MPTCP RFC 8684
- Teltonika RUTM30 / RUT241 documentation
- 3GPP TS 24.301 (EMM reject causes, including "EPS services not allowed in this PLMN")

---

*Last updated: 8 Oct 2026*
