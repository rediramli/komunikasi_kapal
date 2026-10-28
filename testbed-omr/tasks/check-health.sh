# Read-only health check of the video path, RPi side.
#   ./run.sh rpi tasks/check-health.sh
# Companion VPS check:  ./run.sh vps tasks/vps-health.sh
ok(){ echo "  PASS  $1"; }; bad(){ echo "  FAIL  $1"; }
opt(){ { printf 'OPTIONS rtsp://%s:%s/x RTSP/1.0\r\nCSeq: 1\r\n\r\n' "$1" "$2"; sleep 1; } | timeout 4 nc "$1" "$2" 2>/dev/null | head -1; }
echo "== RPi health $(date -u +%FT%TZ) =="

# 1. clock sane (RPi4 has no RTC; must be stepped after boot)
Y=$(date -u +%Y); [ "${Y:-0}" -ge 2026 ] && ok "clock year=$Y" || bad "clock year=$Y (RTC/NTP: run omr-timesync)"

# 2. VPN consistency
V=$(uci -q get openmptcprouter.settings.vpn)
if [ "$V" = openvpn ]; then
  pgrep -f 'openvpn' >/dev/null && ok "settings.vpn=openvpn and openvpn running" || bad "vpn=openvpn but openvpn NOT running"
  pgrep -f 'glorytun-udp' >/dev/null && bad "glorytun-udp STILL running (should be stopped)" || ok "glorytun-udp not running"
else
  bad "settings.vpn=$V (expected openvpn)"
fi

# 3. tun0 overlay IP
IP=$(ip -4 addr show tun0 2>/dev/null | sed -n 's/.*inet \(10\.255\.252\.[0-9]*\).*/\1/p')
[ -n "$IP" ] && ok "tun0 ip=$IP" || bad "tun0 has no 10.255.252.x IP (OpenVPN down)"

# 4. tunnel reachability + MTU (big DF packet must pass)
ping -c1 -W2 10.255.252.1 >/dev/null 2>&1 && ok "VPS tun end 10.255.252.1 reachable" || bad "VPS tun end unreachable"
ping -c1 -W2 -M do -s 1372 10.255.252.1 >/dev/null 2>&1 && ok "1400B DF ping OK (no MTU blackhole)" || bad "1400B DF ping FAILS (MTU/MSS problem)"

# 5. camera DNAT rules loaded
nft list chain inet fw4 dstnat 2>/dev/null | grep -q 'dport 18554' && ok "D-Link DNAT 18554 present" || bad "D-Link DNAT 18554 MISSING"
nft list chain inet fw4 dstnat 2>/dev/null | grep -q 'dport 18555' && ok "Hikvision DNAT 18555 present" || bad "Hikvision DNAT 18555 MISSING"

# 6. cameras answer RTSP (direct from the RPi)
echo "$(opt 192.168.100.20 554)"   | grep -q '200 OK' && ok "D-Link (192.168.100.20) RTSP 200" || bad "D-Link no RTSP reply"
echo "$(opt 192.168.101.151 554)"  | grep -q '200 OK' && ok "Hikvision (192.168.101.151) RTSP 200" || bad "Hikvision no RTSP reply"

# 7. sampler + dashboard
pgrep -f omr-live.sh >/dev/null && ok "twin sampler running" || bad "twin sampler (omr-live.sh) not running"
echo "== done =="
