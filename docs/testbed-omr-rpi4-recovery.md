# Testbed OMR — RPi4 recovery after power-off (28 Oct 2026)

Reference for bringing the two-camera video path back after the RPi4 is powered
off for a while. Topology: RPi4 OpenMPTCProuter (OMR) ↔ DigitalOcean VPS
`168.144.105.155` (SSH port 65222) over an OpenVPN tunnel (`tun0`,
`10.255.252.0/24`); MediaMTX on the VPS serves HLS/WebRTC/RTSP; cameras reach the
VPS via DNAT on the RPi (D-Link `192.168.100.20`→`:18554`, Hikvision
`192.168.101.151`→`:18555`).

## Root causes found this round

1. **Clock (RPi4 has no RTC).** On boot `sysfixtime` sets the clock to the newest
   file mtime (≈ power-off time, days in the past). `ntpd` starts before the
   tunnel/internet is up, fails, and does not recover in time, so TLS-dependent
   services (HTTPS, Tailscale) fail on the wrong clock. NTP itself works fine once
   the tunnel is up (tested: `busybox ntpd -q` returns a reply, offset ≈ 0).

2. **VPS route reverting to a dead Glorytun interface.** The active VPN is
   OpenVPN, but the **Glorytun services were still running on the VPS**
   (`glorytun-udp@tun0`, `glorytun-tcp@tun0`) and the OMR client config still had
   the **stale Glorytun peer** `vpnremoteip = 10.255.254.2`. `omr-service`
   re-installs `192.168.100.0/24 via <vpnremoteip>` every ~20–30 s, so the LAN
   route kept pointing at `gt-udp-tun0` (which, once Glorytun was stopped, became
   `linkdown`). TCP connected but RTSP/video timed out.

3. **MediaMTX pointing at an ephemeral tun0 IP.** Sources were set to
   `@10.255.252.2:` (the RPi's previous OpenVPN IP); after reconnect the RPi came
   up as `10.255.252.3`, so MediaMTX connected to nobody and timed out.

> The MTU/MSS blackhole suspected earlier had already cleared on reconnect:
> `ping -M do -s 1372` (1400 B, DF) passes 0 % loss both ways. `check-health.sh`
> keeps a guard for it.

## Fix applied

- **VPS:** stopped **and disabled** `glorytun-udp@tun0` / `glorytun-tcp@tun0`;
  corrected `vpnremoteip` → `10.255.252.3` (and `vpnlocalip` → `10.255.252.1`) in
  `/etc/openmptcprouter-vps-admin/omr-admin-config.json` (backup kept); set
  `192.168.100.0/24 via 10.255.252.3 dev tun0` (now held by omr-service because
  vpnremoteip matches). MediaMTX sources repointed to the **stable LAN IP**
  `192.168.100.1` (backup kept). Verified with `ffprobe`:
  - `dlink` → H264 2560×1440 @25 + AAC
  - `hik`  → HEVC 2560×1440 @25 + AAC
- **RPi:** installed `/root/omr-timesync.sh` — on boot it waits for the tunnel,
  steps the clock via NTP (falls back to the VPS clock), then restarts Tailscale.
  Hooked into `/etc/rc.local` (`(sh /root/omr-timesync.sh &)` before `exit 0`) and
  a `*/15` cron runs it with `save` (fake-hwclock; its file mtime lets
  `sysfixtime` restore a recent time next boot).

## Recovery procedure (idempotent scripts)

Run from REDLAB in `testbed-omr/` (scripts are piped over SSH, no paste issues):

    ./run.sh rpi tasks/recover-after-poweroff.sh      # clock, VPN/tun0, camera DNAT, sampler
    ./run.sh vps tasks/vps-recover-poweroff.sh        # retire Glorytun, align vpnremoteip+route, MediaMTX
    ./run.sh rpi tasks/check-health.sh                # verify RPi side
    ./run.sh vps tasks/vps-health.sh                  # verify VPS side

`vps-recover-poweroff.sh` auto-detects the RPi's current OpenVPN IP on
`10.255.252.0/24`, so it self-heals the ephemeral-IP case (`.2` vs `.3`).

## Persistent vs temporary

| Item | State |
|---|---|
| Glorytun on VPS stopped **and disabled** | **persistent** (won't restart on boot) |
| MediaMTX sources = `192.168.100.1` (yml edited, backup) | **persistent** |
| RPi clock boot-sync (`rc.local` + cron + `omr-timesync.sh`) | **persistent** |
| `vpnremoteip` = `10.255.252.3` in OMR config | **persistent, but tied to the current RPi IP** — if the RPi reconnects to a different OpenVPN IP, re-run `vps-recover-poweroff.sh` (it re-detects and re-aligns) |
| VPS LAN route `via tun0` | kept live by omr-service while vpnremoteip matches; re-asserted by the recovery script |

## Still open / recommended

- **Pin the RPi OpenVPN IP.** The RPi is at `.3` though `ccd/ipp_tcp.txt` persists
  `.2`; a stale session bumped it. A clean OpenVPN client restart (tunnel blip,
  needs approval) should reclaim `.2` and make `vpnremoteip` stable for good.
- **Dashboard "Switch Transport" safety** (not yet added): after a transport
  switch, verify `tun0` has an IPv4 and the tunnel end pings; auto-revert to
  OpenVPN on failure.
- Full reboot verification of the clock boot-hook needs a controlled RPi reboot.

## Security notes honored

Credentials never printed/committed; RTSP URLs masked (`admin:***@`); configs
backed up before edits (`*.bak.<ts>`); `mediamtx.yml`, keys and
`openmptcprouter_config.txt` are not committed; no uci `src='vpn'` port-forwards;
VPN-service change (Glorytun stop/disable) was done only after explicit approval.
