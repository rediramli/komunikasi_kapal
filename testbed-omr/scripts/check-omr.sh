#!/bin/sh
# Quick health check of the OMR router <-> VPS path. Prints no secrets.
echo "== VPS config";  uci show openmptcprouter.vps | grep -E "\.ip=|error|kernel|omr_version|get_config"
echo "== processes";   ps w | grep -E "ss-|ssservice|sslocal|xray|v2ray|glorytun|tailscaled" | grep -v grep
echo "== tun0";        ip -br addr show tun0 2>&1
echo "== ping VPS tunnel end"; ping -c2 -W2 10.255.255.1 | tail -1
echo "== public IP (should be the VPS)"; curl -s -m 15 https://ifconfig.me; echo
echo "== routes";      ip route | head -5
echo "== MPTCP endpoints"; ip mptcp endpoint show
echo "== WAN pings"
for i in wan1 wan2 phy0-sta0; do
	ip link show "$i" >/dev/null 2>&1 && printf "%-10s " "$i" && ping -c2 -W2 -I "$i" 8.8.8.8 | tail -1
done
echo "== tailscale";   tailscale status 2>/dev/null | head -2
