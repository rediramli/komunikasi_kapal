echo "== add 192.168.110.250/24 back to eth0 (live)"
ip addr add 192.168.110.250/24 dev eth0 2>&1 || echo "(maybe already present)"
ip -br addr show eth0 | tr ' ' '\n' | grep -E '192.168' | sed 's/^/  /'
echo "== route to camera now"
ip route get 192.168.110.2 | head -1
echo "== ping + OPTIONS camera"
ping -c2 -W2 192.168.110.2 2>&1 | tail -1
printf "OPTIONS rtsp://192.168.110.2/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 192.168.110.2 554 | tr -d '\r' | sed -n '1p'
echo DONE
