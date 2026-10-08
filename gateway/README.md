# Gateway — Raspberry Pi Maritime MPTCP Gateway

> Runs on the RPi 5 aboard PSA Agility. User: `fctlab@raspberrypi`.
> Code lives at `~/maritime-stats/` on the device.

## What this component does

The RPi is the single point of connectivity for all devices aboard the vessel.
It bonds two cellular links (RUTM30/Singtel 5G + RUT241/Simba 4G) using Linux
kernel MPTCP, classifies traffic into three priority tiers using nftables, and
reports telemetry to the shore server.

## Directory layout

```
gateway/
├── scripts/           # Python collectors and senders
│   ├── platform_stats.py      # link stats collector (timer-driven, ~30s)
│   ├── drivetest_sender.py    # GPS + RF signal combiner (every 5s)
│   ├── benchmark_sender.py    # iperf3 wrapper
│   ├── benchmark_listener.py
│   ├── gps_sender.py          # GPS reader (currently broken — antenna issue)
│   ├── read_gps.py
│   ├── mqtt_bridge.py         # MQTT → tier ports
│   ├── publish_pyxis_replay.py # AIS replay
│   └── wifi_graph.py          # WiFi visualization
│
├── systemd/           # Unit files
│   ├── maritime-stats.service     # oneshot, triggered by timer
│   ├── maritime-stats.timer       # fires every ~30s
│   ├── maritime-drivetest.service
│   ├── maritime-gateway.service
│   ├── maritime-wifi-ap.service
│   ├── mptcp-limits.service       # MPTCP setup at boot
│   └── maritime-tier.service      # tier classification (persistence TBD)
│
├── network/           # Network configuration
│   ├── setup_mptcp.sh       # MPTCP endpoints + policy routing
│   ├── setup_wifi_ap.sh     # wlan0 AP setup
│   ├── fix_ap.sh            # AP recovery script
│   └── nftables-rules.conf  # 3-tier traffic classification
│
└── diagnostics/       # Troubleshooting tools
    └── check_rut241.sh      # Full diagnostic (interface, routing, MPTCP, services)
```

## Deploying changes

```bash
# From your local machine, copy to RPi
scp scripts/platform_stats.py fctlab@raspberrypi:~/maritime-stats/

# On the RPi, restart the relevant service
sudo systemctl restart maritime-stats.timer

# For systemd unit changes
sudo cp systemd/maritime-stats.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart maritime-stats.timer
```

## Gotchas

See main README sections 8.3, 8.4, 8.5, 8.6, 8.7, 8.10.
