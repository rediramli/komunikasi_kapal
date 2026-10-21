echo "OPTIONS via 192.168.100.1:18554: $(printf 'OPTIONS rtsp://192.168.100.1:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n' | timeout 6 nc 192.168.100.1 18554 2>/dev/null | head -1)"
echo "route: $(ip route get 192.168.100.1 2>&1 | head -1)"
