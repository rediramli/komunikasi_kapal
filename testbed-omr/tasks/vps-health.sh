# Read-only health check of the video path, VPS side.
#   ./run.sh vps tasks/vps-health.sh
ok(){ echo "  PASS  $1"; }; bad(){ echo "  FAIL  $1"; }
echo "== VPS health $(date -u +%FT%TZ) =="

# RPi OpenVPN IP (the connected client on 10.255.252.0/24)
RPIIP=""; for i in 2 3 4 5 6; do ping -c1 -W1 10.255.252.$i >/dev/null 2>&1 && { RPIIP=10.255.252.$i; break; }; done
[ -n "$RPIIP" ] && ok "RPi reachable on OpenVPN at $RPIIP" || bad "no RPi found on 10.255.252.0/24 (tunnel down)"

# 1. glorytun leftovers must be OFF
for s in glorytun-udp@tun0 glorytun-tcp@tun0; do
  systemctl is-active "$s" >/dev/null 2>&1 && bad "$s still ACTIVE (should be stopped)" || ok "$s stopped"
done

# 2. route to RPi LAN must go via OpenVPN tun0, not a glorytun interface, not linkdown
RT=$(ip route show 192.168.100.0/24)
echo "$RT" | grep -q 'dev tun0' && ! echo "$RT" | grep -qi 'linkdown' && ok "LAN route via tun0: $RT" || bad "LAN route wrong: $RT"

# 3. vpnremoteip in OMR config matches the live RPi IP (so omr-service keeps the route)
VR=$(jq -r '.users[0].openmptcprouter.vpnremoteip' /etc/openmptcprouter-vps-admin/omr-admin-config.json 2>/dev/null)
[ -n "$RPIIP" ] && [ "$VR" = "$RPIIP" ] && ok "vpnremoteip=$VR matches RPi" || bad "vpnremoteip=$VR != RPi $RPIIP (omr-service will mis-route)"

# 4. MediaMTX up + sources point at the stable LAN IP (not an ephemeral tun0 IP)
pgrep -f mediamtx >/dev/null && ok "mediamtx running" || bad "mediamtx NOT running"
if grep -q '@192.168.100.1:' /etc/mediamtx/mediamtx.yml 2>/dev/null; then ok "mediamtx sources use stable 192.168.100.1"; else bad "mediamtx sources NOT 192.168.100.1 (check for stale tun0 IP)"; fi

# 5. camera RTSP reachable through the DNAT (OPTIONS)
for p in 18554 18555; do
  R=$({ printf 'OPTIONS rtsp://192.168.100.1:%s/x RTSP/1.0\r\nCSeq: 1\r\n\r\n' "$p"; sleep 1; } | timeout 5 nc 192.168.100.1 "$p" 2>/dev/null | head -1)
  echo "$R" | grep -q '200 OK' && ok "camera via DNAT :$p -> 200 OK" || bad "camera via DNAT :$p no reply"
done
echo "== done =="
