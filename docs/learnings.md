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

### MPTCP `bpf_red` (redundant) scheduler breaks the OpenVPN tunnel
- **Discovered:** 19 Oct 2026
- **Detail:** Switching the kernel MPTCP scheduler to `bpf_red` (redundant) on the RPi put the OMR OpenVPN client (`--mptcp`, TCP to the VPS) into a permanent restart loop: TCP connected and the client wrote its TLS hello (`TCP/UDP write bytes,80` in the status file) but **read 0 bytes back**, then `[UNDEF] Inactivity timeout (--ping-restart)` fired after 60 s and it restarted — `tun0` never came up. The camera and general traffic went down with it. Reverting `net.mptcp.scheduler` to `default` is required; `bpf_red` is not usable on this stack.
- **Also:** a kernel MPTCP scheduler is chosen **per connection at creation**, so a live `sysctl net.mptcp.scheduler=X` only affects *new* connections. The OMR OpenVPN tunnel is one long-lived connection, so it keeps its old scheduler until it reconnects (restart openvpn), and the OMR proxy connections (shadowsocks `sslocal`, ports 65280+) keep theirs too. Persist a choice in `network.globals.mptcp_scheduler` (OMR maps it at boot); the shipped value here is `blest`, which the modern-kernel BPF set does not have, so boot falls back to the in-kernel `default`.
- **Why "only one SIM flows" is usually normal:** wan1/Simba RTT ≈ 12 ms, wan2/Singtel ≈ 90 ms (~8×). An aggregating scheduler (`default`/`blest`) sends a single light stream (~2 Mbps) almost entirely over the low-RTT link and only spills to the slow one when the fast one saturates or there are many connections. That is correct bonding, not a fault. Forcing both links for one light stream needs redundancy, which `bpf_red` would give but it breaks the tunnel here. The failover test leaves `bpf_bkup` (backup-only) set — revert it to `default`/`blest` afterwards or wan2 stays backup-only.

### Restarting `openvpn@tun0` on the VPS can wedge it in D-state (needs a VPS reboot)
- **Discovered:** 19 Oct 2026
- **Detail:** `systemctl restart openvpn@tun0.service` on the OMR VPS left the old `openvpn --mptcp` process stuck in uninterruptible sleep (`ps stat Ds`, `wchan lock_sock`). It ignored SIGTERM **and SIGKILL** ("Processes still around after SIGKILL. Ignoring"), kept holding the `:65301` listen socket, and the unit hung in `deactivating`/`activating` so no fresh server could bind. Clients then connect TCP but get no handshake response. A D-state process cannot be killed from userspace — the **only** recovery is a VPS reboot. Avoid restarting the VPS-side OpenVPN MPTCP server; if a client-side reconnect is needed, restart openvpn on the RPi instead.

### OMR RPi reboot drops non-uci helper state (camera LAN IP, twin sampler)
- **Discovered:** 19 Oct 2026
- **Detail:** Two things set up outside uci did not survive an RPi reboot. (1) The secondary eth0 address `192.168.110.250/24` that gives the RPi its direct route to the camera LAN (`192.168.110.0/24`) was added manually, so after reboot `ip route get 192.168.110.2` fell back to `via tun0` and the camera was unreachable (MediaMTX → `400 Bad Request`). Fixed by appending `ip addr add 192.168.110.250/24 dev eth0` to `/etc/rc.local`. (2) The Digital-Twin 1 Hz sampler (`/root/omr-live.sh` → `/tmp/omr_live.csv`) did not auto-restart: its auto-start guard does `P=$(cat /tmp/omr_live.pid); kill -0 "$P" || start`, and after reboot the pid file is gone so `P` is empty — **BusyBox `kill -0 ""` returns success**, so the guard thinks it is alive and never starts it (dashboard shows 0 / "Connecting…"). Start it explicitly, and guard with `[ -n "$P" ] && kill -0 "$P"` — or just `pgrep -f omr-live.sh >/dev/null || start`, which the twin now uses.

### Camera stream dies on WAN failover because the RPi's tunnel IP changes
- **Discovered:** 19 Oct 2026
- **Detail:** On a failover (e.g. Simba/wan1 cut → traffic moves to Singtel/wan2) the OMR OpenVPN client reconnects and OpenVPN assigns it a **different** tunnel IP from the pool — it flips between `10.255.252.2` and `.3` (the old session lingers in the server routing table until `ping-restart`, 480 s, frees `.2`). OMR auto-updates the VPS route `192.168.100.0/24 via <current tunnel IP>`, but `mediamtx.yml` hard-coded `rtsp://admin:…@10.255.252.2:18554/…`, so after a flip to `.3` MediaMTX pointed at a dead IP and the stream stopped (HLS/RTSP returned, but no frames).
- **Fix:** point the MediaMTX source at the RPi's **stable LAN IP** `192.168.100.1:18554` instead of the tunnel IP. The RPi DNAT (`ip saddr 10.255.252.1 tcp dport 18554 dnat to 192.168.110.2:554`) matches on the VPS's source IP, not the destination, so any VPS-originated packet to `…:18554` reaches the camera regardless of which tunnel IP is live, and `192.168.100.1` is reachable via the auto-updated route in both directions. Failover and fail-back are then seamless.

### Twin "auto test" must not include `bpf_red`
- **Discovered:** 19 Oct 2026
- **Detail:** The Digital-Twin dashboard let `bpf_red` be selected/applied (and the 7-min auto test would run it), which restarts the RPi OpenVPN under a redundant scheduler and wedges the tunnel (see the `bpf_red` entry above) — during a live test this took down the camera and needed a VPS reboot. The twin now blocks `bpf_red` server-side in `live_server.py` (`BLOCKED_SCHED`, returns HTTP 400) and filters it out of the dropdown, so neither a manual apply nor the auto test can select it.

### OpenVPN `--mptcp` wedges on disruption; Glorytun UDP is the robust VPN for the camera
- **Discovered:** 20 Oct 2026
- **Why OpenVPN `--mptcp` was the wrong transport here:** OMR's "MPTCP over VPN" wraps the kernel MPTCP connection inside OpenVPN (meant for ISPs that filter MPTCP). On this VPS kernel the openvpn `--mptcp` process **deadlocks in D-state (`lock_sock`)** whenever its MPTCP connection is disrupted — a scheduler change+restart, a WAN cut/failover, or a reconnect — and only a VPS reboot clears it. It also rode mostly one subflow (MPTCP favours the low-RTT WAN), so only one SIM carried a single light stream. Every "random" outage this session traced back to disrupting this tunnel.
- **Fix — switch the Default VPN to Glorytun UDP** (OMR LuCI → System → OpenMPTCProuter → wizard → Default VPN = Glorytun UDP → Save & Apply; it syncs the VPS via the omr-admin API). Glorytun UDP does its own multipath aggregation (no kernel MPTCP), has `persist` + dynamic-rate detection (built for cellular), and does not deadlock. Result: the camera stream **aggregates across both SIMs roughly evenly** (Simba ≈ Singtel ≈ 400–700 kbps each), and WAN cuts no longer wedge anything.
- **One manual step after the switch:** OMR auto-updates the VPS route `192.168.100.0/24 via <glorytun tun IP 10.255.254.2>`, but the RPi camera DNAT still matched the old OpenVPN VPS source `10.255.252.1`. Widen `/etc/dlink/*.nft` to `ip saddr { 10.255.252.1, 10.255.254.1 }` (openvpn + glorytun VPS tunnel IPs) and `fw4 reload`. MediaMTX source stays `192.168.100.1:18554`. OpenVPN config is left intact (just disabled) for rollback.

### Switching transport back to Glorytun UDP can leave the daemon dead (OpenVPN steals tun0)
- **Discovered:** 21 Oct 2026
- **Symptom:** On the dashboard, switching transport Glorytun UDP → Glorytun TCP (MPTCP) → back to Glorytun UDP left the camera stream dead. `tun0` still showed the UDP peer IP `10.255.254.2` and the VPS route `192.168.100.0/24 via 10.255.254.2 dev gt-udp-tun0` was correct, **but VPS → RPi LAN (192.168.100.1) was 100% packet loss** — tunnel "up on paper", data plane dead. MediaMTX reported `no stream is available`.
- **Root cause:** The `glorytun-udp` daemon on the RPi was **not running**. `logread` showed `glorytun-udp: couldn't create tun device` in a restart loop. OMR also keeps **OpenVPN enabled and running** (it owns `tun0`, range `10.255.252.x`); OpenVPN re-grabs `tun0` so glorytun can't create its device. The stale `tun0` even carried OpenVPN's `10.255.252.2/24` alongside the glorytun peer IP. The interface + IP persisted, so the old `vpn_set()` success check (tun0 has the IP) returned a **false "done"** while the daemon was dead.
- **Manual recovery:** on the RPi, `ip link del tun0` → `/etc/init.d/glorytun-udp restart` → re-add `ip addr add 10.255.254.2/32 peer 10.255.254.1 dev tun0; ip link set tun0 up`. Verify with `pidof glorytun-udp` (daemon alive) and `ping 10.255.254.1` (tunnel data plane). Then the VPS reaches `192.168.100.20:554` (camera via DNAT on `192.168.100.1:18554`) and MediaMTX pulls on demand (HLS 200, H.264+AAC).
- **Permanent fix (in `twin/live_server.py` `vpn_set()`):** before (re)starting the target glorytun, **stop OpenVPN and delete the stale tun device**, then **verify the daemon is actually alive with `pidof`** (self-match-proof — never `pgrep -f`, which matches the ssh command itself) and retry the free+restart up to 3× if it isn't. Only emit `done` when the daemon is alive **and** the peer IP is present, so a dead daemon can't masquerade as success.
- **Note:** the camera now lives at `192.168.100.20:554` on the LAN (reached via the Omada switch after the Ruijie→Omada swap); RPi `192.168.100.1:18554` DNATs to it with VPS source allowlist `{10.255.252.1, 10.255.254.1, 10.255.255.1}`.
