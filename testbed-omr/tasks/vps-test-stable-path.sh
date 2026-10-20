echo "== OPTIONS to RPi stable LAN IP 192.168.100.1:18554 (via auto-updated route)"
printf "OPTIONS rtsp://192.168.100.1:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 192.168.100.1 18554 2>/dev/null | head -1 || echo "(no response)"
echo "== route check"
ip route get 192.168.100.1 2>&1 | head -1
echo DONE
