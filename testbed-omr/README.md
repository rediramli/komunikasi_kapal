# Testbed — OpenMPTCProuter on Raspberry Pi 4

Lab testbed for trying multi-link features **before** they go onto the vessel
gateway (RPi 5 on PSA Agility). It uses OpenMPTCProuter (OMR) on the RPi 4,
with a shore-side OMR VPS acting as the MPTCP aggregator, so that plain-TCP
traffic from LAN devices (e.g. AIS forwarding, camera streams) gets bonded.

> Status (13 Oct 2026): router ↔ VPS connected (API login OK, config pulled).
> Teltonika WANs not yet attached; only a temporary Wi-Fi uplink is active.
> Next: attach RUTM30 (wan1) and RUT241 (wan2), verify bonding, then camera
> stream + GNSS logging for the Singapore-waters drive test.

**Read [`docs/learnings.md`](../docs/learnings.md#openmptcprouter-testbed) first** —
most of the setup time went into the traps listed there.

---

## 1. Components

| Item | Detail |
|---|---|
| Router | Raspberry Pi 4 Model B Rev 1.5, 128 GB SD |
| Firmware | OpenMPTCProuter v0.63 (OpenWrt, kernel 6.12, package manager `apk`) |
| WAN 1 | RUTM30 — Singtel 5G (same as vessel) |
| WAN 2 | RUT241 — Simba LTE (same as vessel) |
| WAN 3 (optional) | RUTM16 — different operator / spare |
| Temporary uplink | RPi on-board Wi-Fi as client (`wwan`, iface `phy0-sta0`) |
| Remote access | Tailscale (hostname `omr-rpi4`) |
| VPS | DigitalOcean `omr-vps`, SGP1, Debian 13, 1 GB RAM + 2 GB swap, OMR VPS 0.1082, kernel 6.18 omr |
| Camera (planned) | Logitech C270 (UVC, MJPEG 720p30) |
| GNSS (planned) | USB GNSS dongle |

## 2. Topology

```
                 ┌──────────── switch ────────────┐
Laptop ──────────┤                                │
RPi4 eth0 ───────┤  wan1@eth0 (macvlan) 192.168.1.100 → RUTM30 192.168.1.1 (Singtel 5G)
                 │  wan2@eth0 (macvlan) 192.168.2.100 → RUT241 192.168.2.1 (Simba LTE)
                 └────────────────────────────────┘
RPi4 LAN: 192.168.100.1/24 (eth0)

RPi4 ══ MPTCP (shadowsocks / glorytun) ══> OMR VPS 168.144.105.155 ──> Internet
```

- The RPi 4 has one Ethernet port. OMR's default image puts `wan1`/`wan2` as
  **macvlan on eth0**, so all routers share one unmanaged switch, separated by
  subnet. **Turn DHCP off on both Teltonikas**, otherwise LAN clients get a
  lease from the Teltonika and bypass OMR.
- RUT241 LAN must be moved from the default `192.168.1.1` to `192.168.2.1`.
- Use a gigabit switch and Cat5e/6 — eth0 negotiated 100 Mbps on the first try.

### Addresses

| Device | Address | Access |
|---|---|---|
| OMR router (LAN) | `192.168.100.1` | `ssh root@192.168.100.1`, LuCI `http://192.168.100.1` |
| OMR router (Tailscale) | `omr-rpi4` | `ssh root@omr-rpi4` |
| OMR VPS | `168.144.105.155` | `ssh -p 65222 root@168.144.105.155`, API `:65500` |

The SIT network blocks outbound SSH on port 22; port 65222 works from REDLAB.

## 3. Router setup (from a fresh OMR image)

Run in this order. Scripts are in [`scripts/`](scripts/); copy them over with
`scp -O` (dropbear has no SFTP server).

> The scripts were written up on 13 Oct 2026 from the commands that were run
> by hand during the first setup. They have **not yet been run end-to-end as
> scripts** on a fresh image — treat the first run as a test and report back.

1. **Fix read-only root** — `scripts/fix-fstab-ro.sh`, then reboot.
2. **Root password** — `passwd` (LuCI keeps nagging until set).
3. **Clock** — if the date is wrong TLS fails: `ntpd -q -n -p 162.159.200.1`.
4. **Temporary uplink (optional)** — `scripts/setup-wwan-sta.sh "<SSID>" [psk]`.
   While no Teltonika is attached keep `wan1`/`wan2` from stealing the default route:
   ```sh
   uci set network.wan1.auto='0'; uci set network.wan2.auto='0'; uci commit network
   ifdown wan1; ifdown wan2
   ```
5. **Tailscale** — the package is not in the OMR repo. Download the static
   `tailscale_<ver>_arm64.tgz` from <https://pkgs.tailscale.com/stable/#static> on a
   laptop, `scp -O` it to `/tmp`, then run `scripts/install-tailscale.sh` and
   `scripts/setup-tailscale-fw.sh`.
6. **Connect to the VPS** — `scripts/set-vps.sh <VPS_IP>` (see §4).
7. **Attach Teltonikas** — set `wan1`/`wan2` back to `auto='1'`, `ifup wan1; ifup wan2`.

## 4. VPS setup

```sh
# Debian 12/13 x64, >= 1 GB RAM. 512 MB gets OOM-killed during install.
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
systemctl disable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer

apt update && apt install -y tmux wget
tmux new -s omr
wget -O /root/omr-install.sh https://www.openmptcprouter.com/server/debian-x86_64.sh
sh /root/omr-install.sh 2>&1 | tee /root/omr-install.log
reboot          # SSH moves to port 65222 afterwards
```

The router logs in to the VPS API as user `openmptcprouter`. **Take its password
from `/etc/openmptcprouter-vps-admin/omr-admin-config.json`, not from
`/root/openmptcprouter_config.txt`** — after a re-run of the installer the
"Server key" in the text file was the *admin* user's password.
`scripts/set-vps.sh` does this over SSH and verifies the login before saving.

Never commit `openmptcprouter_config.txt` or any key to this repo.

## 5. Verification

`scripts/check-omr.sh` on the router prints everything below.

| Check | Expected |
|---|---|
| `uci show openmptcprouter.vps` | `admin_error='0'`, `get_config='0'`, VPS kernel/version filled in |
| proxy / VPN processes | shadowsocks or xray + glorytun running |
| `ip -br addr show tun0` | has an address |
| `ping 10.255.255.1` | replies (VPS end of the tunnel) |
| `curl https://ifconfig.me` | **VPS public IP** (traffic exits via the aggregator) |
| `ip mptcp endpoint show` | one endpoint per WAN, none for `tailscale0` |
| on VPS: `ss -tiM` | MPTCP connections from the router with >1 subflow |

## 6. Drive-test plan (draft)

- Stream the C270 (MJPEG in → H.264 out, TCP/RTMP so it goes through the proxy)
  from a LAN device to an ingest server **behind** the VPS, so the path mirrors
  AIS → Jason Marine.
- Step the bitrate (1 → 2 → 4 → 8 Mbps); bonding only matters at the top.
- Log at 1 Hz: GNSS position, per-router RSRP/RSRQ/SINR/PCI/band/**registered
  PLMN**, per-subflow MPTCP bytes, RTT per WAN, stream bitrate/stalls.
- Lab failover test first (pull one WAN cable mid-stream).

## 7. D-Link camera → VPS (RTSP/HLS over MPTCP)

Goal: view the D-Link DCS-8526LH (LAN-side, behind the Ruijie at `192.168.110.2`)
from the public VPS, so the path mirrors a vessel camera → shore.

**Camera prerequisite (the hard part):** in the mydlink app → Device Settings,
**ONVIF must be On**. With ONVIF Off the camera answers `OPTIONS` but returns
`454 Session Not Found` to every `DESCRIBE`/`SETUP` — no `401` challenge — and no
amount of RTSP-client tweaking helps. Enabling ONVIF needs the camera to reach the
mydlink cloud first, so it also needs working internet. See
[`docs/learnings.md`](../docs/learnings.md) → "RTSP returns 454 until ONVIF is enabled".

**Reaching the camera from the VPS (tunnel-only, no public exposure):**
- RPi has a direct route to the camera LAN (`192.168.110.0/24 dev eth0`).
- nftables includes on the RPi (not a `src='vpn'` uci redirect — that leaks to a
  public VPS DNAT) map the VPS tunnel IP to the camera, saddr-restricted:
  `/etc/dlink/dnat.nft` DNAT `10.255.252.1 :18554 → 192.168.110.2:554`,
  plus matching forward/snat includes.

**MediaMTX on the VPS** (`/etc/mediamtx/mediamtx.yml`, `chmod 600`, runs as root):
```yaml
paths:
  dlink:                                   # main, H.264 2560x1440
    source: rtsp://admin:<PASSWORD>@10.255.252.2:18554/live/profile.0
    rtspTransport: tcp
    sourceOnDemand: yes
  dlink_sub:                               # sub, H.264 1280x720
    source: rtsp://admin:<PASSWORD>@10.255.252.2:18554/live/profile.1
    rtspTransport: tcp
    sourceOnDemand: yes
```
Enabling ONVIF can change the RTSP password; a `401` in the MediaMTX log (not `454`)
means the stored password is stale. `admin` is the RTSP user; the password is kept
only in `mediamtx.yml`, never in git or chat.

**View / verify:**
- VLC: `rtsp://<vps>:8554/dlink`
- Browser (HLS, H.264 only): `http://<vps>:8888/dlink/`
- `ffprobe -rtsp_transport tcp rtsp://<vps>:8554/dlink` → `h264 2560x1440` + `aac`
- Path rides the OMR MPTCP tunnel: `ip mptcp endpoint show` (one per WAN) and, on
  the VPS, `ss -tiM` shows the connection with `subflows_total:2`.
