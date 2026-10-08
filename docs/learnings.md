# Learnings — Mistakes Made and Lessons Learned

> This file exists to prevent AI agents and future contributors from
> re-discovering known issues. Add to it when you debug something and find the
> cause was different from your hypothesis.

---

## Measurement & Data Collection

### AT+QCSQ is cached, AT+QENG is measured
- **Discovered:** 5 Oct 2026
- **Impact:** Three wrong debugging hypotheses (stale endpoints, missing routing, RRC idle) before identifying the real cause
- **Detail:** `AT+QCSQ` returned exactly −99 dBm six consecutive times while SINR varied. It reads from a cache refreshed at the legacy signal-quality rate. `AT+QENG="servingcell"` reads from the modem measurement layer on each call.
- **Offset:** 2–3 dB — same order as the propagation effects being studied
- **Rule:** Always use QENG. Always record which command produced each RSRP value.

### Fabricated GPS coordinates from Data to Server
- **Discovered:** Sep 2026
- **Impact:** 106,622 rows with fake lat/lon in `measurements` table
- **Detail:** Teltonika Data to Server JSON template includes `lat`/`lon` fields by default. These come from the router's internal GPS, not the RPi's GNSS. With no antenna fix, the values are fabricated.
- **Fix:** Remove lat/lon from JSON template on both routers. RF data in those rows is preserved — only coordinates were nulled.

### leaflet.heat doesn't work for dense grids
- **Discovered:** Sep 2026
- **Detail:** 89×66 grid (5,874 points) saturates into one solid blob. Use canvas painting + bilinear upscale + `L.imageOverlay`.

---

## Network & Connectivity

### PLMN camping on foreign cells in domestic waters
- **Discovered:** 7 Oct 2026
- **Detail:** RUT241 camped on Malaysian cell (MCC 502, Band 28 / 788 MHz) while vessel was at Singapore PSA terminals. 700 MHz propagates far over water — Johor is only a few km from Tuas across open water.
- **Key insight:** Both countries use Band 28. No frequency-based separation. Signal strength alone drives cell selection. A domestic SIM can lose service without crossing any border.
- **Implication for ML:** RF-only models would predict this cell as usable. PLMN identity and registration state must be features.

### MPTCP bonding is end-to-end only
- **Impact:** AIS traffic (94% of forwarded, 2.71 GB Tier 1) is NOT bonded because Ethan's AIS destination server is plain TCP
- **Rule:** Never claim bonded throughput for traffic whose destination doesn't speak MPTCP. A shore-side aggregator is needed for third-party traffic.

### Policy routing: tables 1 and 2, not 100/200
- **Discovered:** 7 Oct 2026 (re-discovered — was correct from deployment)
- **Detail:** `ip rule show` prints `lookup 2` not `lookup 200`. Does not print interface names. `grep eth1` or `grep 200` finds nothing. Rules at pref 5208/5209 using tables 1/2 have been present since deployment.
- **Consequence:** An earlier session added redundant table 200 rules. These are harmless but should be cleaned up.

### Timer-driven oneshot services look dead
- **Detail:** `systemctl is-active maritime-stats.service` returns `inactive` between timer firings. This is normal for oneshot units. Check `systemctl list-timers` instead.
- **Consequence:** Led to false conclusion that "nothing is collecting telemetry." Collector was healthy the entire time.

### iperf3 bonding test pitfalls
- `iperf3 -s -D` may silently fail (Connection refused)
- `speed.cloudflare.com` doesn't speak MPTCP
- `-R` flag tests wrong direction
- Both sides need `mptcpize run`

### Simba coverage gaps
- **Detail:** Simba is the smallest Singapore operator. Coastal/maritime coverage is thinner. At Tuas terminal, RUT241 (Simba) had RSRP −100, RSRQ −20, SINR −5 while RUTM30 (Singtel) worked fine at the same location.
- **Implication:** Two Singapore SIMs ≠ true diversity for maritime. Starlink provides a genuinely different failure mode.

### RUT241 mob1s1a1 autostart disabled
- **Detail:** `autostart: false` and `mwan3.mob1s1a1.enabled='0'` observed. Modem won't auto-reconnect after data session drop.
- **Fix:** Enable via router admin: Network → Interfaces → mob1s1a1.

---

## Grafana & Visualization

### timeColumns is critical
- **Detail:** `frser-sqlite-datasource` requires `timeColumns: ["time","ts"]` in the datasource configuration (UID `afpb2eygfssu8a`). Without it, time-series panels render nothing. This is non-obvious and underdocumented.

### M-AIRMap viewer must be same-origin HTTP
- **Detail:** External HTTPS page → mixed-content blocking when calling HTTP API. Viewer lives on the server at `/home/maritime/static/`.

---

## Heatmap / M-AIRMap

### Synthetic BS placement must be coastline-constrained
- Maritime base stations are coastal only. Training on randomly-placed BS (including open sea) teaches wrong propagation geometry.

### Train/inference BS count mismatch
- Training sees 1 BS per sample. Inference uses 30 estimated BS. Network has never seen a multi-BS scene.

### Calibration factor is a diagnostic
- `RSRP_cal = 4.592 × RSRP_pred + 127.20` — a scale of 4.6 means raw output is badly biased. This is expected given issues 7.1–7.3 but should improve with fixes.

---

## Working practices

### Discuss before producing documents
- The project owner (Redi) prefers to discuss approach before any document or code is produced. Do not generate deliverables without alignment first.

### Honest reporting
- Partial results (e.g. 1/3 failover success) are reported as-is to the supervisor, not inflated.
- Placeholder data is flagged all the way to the UI via `ModuleState.is_placeholder`.
- Calibration and test methodology are always stated alongside accuracy numbers.
