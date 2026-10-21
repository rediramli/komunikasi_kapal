echo "route to camera LAN: $(ip route | grep -E '192.168.100.0' | head -1)"
echo "gt-tun0: $(ip -br addr show gt-tun0 2>/dev/null)"
# ensure route via glorytun TCP peer 10.255.255.2 if missing/wrong
ip route replace 192.168.100.0/24 via 10.255.255.2 dev gt-tun0 2>&1 && echo "route set via 10.255.255.2"
echo "ping RPi tunnel 10.255.255.2: $(ping -c2 -W2 10.255.255.2 2>&1 | tail -1)"
echo "OPTIONS camera via 192.168.100.1:18554: $(printf 'OPTIONS rtsp://192.168.100.1:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n' | timeout 6 nc 192.168.100.1 18554 2>/dev/null | head -1)"
echo DONE
