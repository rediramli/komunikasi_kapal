echo "== VPS tun0 (glorytun end?)"; ip -br addr show tun0 2>&1 | head -1
echo "== gt-udp iface"; ip -br addr | grep -iE 'gt-udp|10.255.254' | head
echo "== route to camera LAN 192.168.100.0/24"; ip route | grep -E '192.168.100|10.255.254' | head
echo "== glorytun-udp server running?"; systemctl is-active glorytun-udp@tun0 2>/dev/null; pgrep -af 'glorytun-udp' | head -1
echo "== reach camera via tunnel (192.168.100.1:18554)?"; printf "OPTIONS rtsp://192.168.100.1:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 192.168.100.1 18554 2>/dev/null | head -1 || echo "(no camera path)"
echo DONE
