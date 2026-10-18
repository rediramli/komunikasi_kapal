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

---

## OpenMPTCProuter testbed

Setup of OMR v0.63 on the lab RPi 4 + OMR VPS on DigitalOcean (12–13 Oct 2026).
Full procedure: [`testbed-omr/README.md`](../testbed-omr/README.md).

### Root filesystem silently read-only
- **Discovered:** 12 Oct 2026
- **Detail:** The OMR rpi4 image ships `/etc/config/fstab` with a mount entry for `/` and `enabled_fsck=1`. At boot, `block` remounts root read-only to fsck it and never returns it to rw. `apk`, `uci commit` and `passwd` all fail ("Read-only file system"), and `passwd` appearing to succeed earlier was misleading.
- **Fix:** Delete the `/` entry from fstab (`testbed-omr/scripts/fix-fstab-ro.sh`).

### OMR resets all TCP when the VPS is unreachable
- **Discovered:** 12 Oct 2026
- **Detail:** With the VPS unreachable (here: the image was still configured for an old VPS, 165.22.245.127), the transparent proxy accepts every TCP connection — including the router's own — and resets it. Symptoms looked like TLS problems (`SSL error reason(5)`, `curl: (35) Connection reset by peer`, Tailscale "fetch control key ... connection reset").
- **Implication for the vessel:** No VPS = no TCP at all, not a fallback to direct links. VPS availability is a single point of failure that must be monitored.

### `openmptcprouter.vps.ip` is a uci LIST
- **Discovered:** 13 Oct 2026
- **Impact:** ~1 h of debugging keys that were actually correct
- **Detail:** `uci set openmptcprouter.vps.ip=<ip>` turns the list into an option. `uci show` prints both identically, but the init script iterates with `config_list_foreach`, finds no server, and logs `Can't get vps token, try later ()` (empty reason = it never tried).
- **Rule:** `uci delete openmptcprouter.vps.ip; uci add_list openmptcprouter.vps.ip=<ip>`.

### OMR VPS "Server key" in the text file can be the admin password
- **Discovered:** 13 Oct 2026
- **Detail:** The installer was run twice (first run OOM-killed). Afterwards the "Server key" line in `/root/openmptcprouter_config.txt` matched the `admin` user, not `openmptcprouter`, and the API answered `Incorrect username or password`.
- **Rule:** Read the `openmptcprouter` user's password from `/etc/openmptcprouter-vps-admin/omr-admin-config.json` and test it with `curl -sk -X POST https://<vps>:65500/token -d "username=openmptcprouter&password=<key>"` before touching the router.

### OMR VPS needs >= 1 GB RAM
- **Detail:** On a 512 MB droplet the installer's `apt-get` was OOM-killed mid-install. Use 1 GB + 2 GB swap, and disable `unattended-upgrades` (it held the dpkg lock right after the resize reboot).

### Tailscale on OMR: no netifd interface for tailscale0
- **Detail:** Declaring `network.tailscale` (`proto none`, device `tailscale0`) makes netifd strip the 100.x address and OMR adds `ip4table`/metric as if it were a WAN → SSH over Tailscale dies. Bind a firewall zone to `device 'tailscale0'` instead and run `tailscale up --netfilter-mode=off`. The tailscale package is not in the OMR repo; use the static arm64 build (download on a laptop — not amd64).

### `service network reload` brings dead WANs back
- **Detail:** With no Teltonika attached, a reload re-enabled `wan1`/`wan2`, the default route moved to a dead link and Tailscale went offline. Keep unused WANs at `auto='0'`.

### Phone hotspot as a temporary uplink is not reliable
- **Detail:** Signal −46 dBm / 72 Mbps PHY, yet RTT 6.7 s at ~27 kbps of traffic — the operator was throttling. Download speed of ~1 KB/s made the VPS installer look broken. Check RTT before blaming the software.

### D-Link DCS-8526LH: RTSP returns 454 until ONVIF is enabled
- **Discovered:** 18 Oct 2026
- **Detail:** The camera's RTSP server (`Server: RtpRtspServer`) answered `OPTIONS` with `200` but replied `454 Session Not Found` to **every** `DESCRIBE`/`SETUP`/`GET_PARAMETER`/`PLAY` — regardless of path (24 paths swept), of auth (none / Basic / Digest), and of client source subnet, and it never sent a `401` challenge. MediaMTX (gortsplib) always DESCRIBEs first and waits for `401`, so it failed. The cause was **ONVIF turned Off** in the mydlink app; on these cameras the local RTSP streaming service is gated behind ONVIF. OPTIONS still answered because the listener is up.
- **Also:** ONVIF can only be toggled from the mydlink app, and the app needs the camera to reach the **mydlink cloud** first ("Linking to the Cloud…" hangs without internet). On the isolated test LAN the camera's internet path (camera → Ruijie → Ruijie WAN → RPi → MPTCP) was down (Ruijie WAN `192.168.100.203` ARP `FAILED`), so setup never completed. Giving the camera internet, finishing cloud link, then enabling ONVIF fixed it.
- **Fix:** mydlink app → Device Settings → **ONVIF = On** (needs the camera online to the cloud). After that `DESCRIBE` returns `401 Digest realm="RtpRtspServer"` and `admin` + the camera password streams `rtsp://<cam>/live/profile.0` (H.264 2560×1440 main, 1280×720 sub; AAC 16 kHz). Diagnostic scripts: `testbed-omr/scripts/rtsptest*.sh`, `testbed-omr/tasks/rtsp-*.sh`.
- **Gotcha:** enabling ONVIF can change the RTSP password, so the value stored in `mediamtx.yml` may need re-entering (`401` in the MediaMTX log with the stream otherwise reachable = wrong credential, not 454).

### OMR copies RPi `src='vpn'` port forwards to the VPS as public DNAT
- **Detail:** A uci redirect on the RPi with `src='vpn'` is auto-propagated by OMR into a **public** DNAT on the VPS, exposing the target (e.g. a LAN camera) to the internet. It happened once and was removed. For tunnel-only reachability use a plain nftables include on the RPi (`/etc/dlink/*.nft`, saddr-restricted to the VPS tunnel IP `10.255.252.1`), never a `src='vpn'` redirect. Verify on the VPS with `nft list ruleset | grep 'dnat ip to 10.255.252.2'` → must be empty.
