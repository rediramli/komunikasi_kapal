echo "== camera reachable from RPi?"
ping -c2 -W2 192.168.110.2 2>&1 | tail -1
echo "== OPTIONS to camera direct"
printf "OPTIONS rtsp://192.168.110.2/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 192.168.110.2 554 | tr -d '\r' | sed -n '1p'
echo
echo "== dlink DNAT rules present after reboot?"
nft list ruleset 2>/dev/null | grep -E '18554|192.168.110.2' | sed 's/admin:[^@]*@/admin:***@/' | head
echo "-- fw4 includes:"
uci show firewall 2>/dev/null | grep -iE 'dlink' | head
echo
echo "== OPTIONS via the DNAT path (from RPi to its own tunnel ip 10.255.252.2:18554)"
printf "OPTIONS rtsp://10.255.252.2:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 10.255.252.2 18554 | tr -d '\r' | sed -n '1p'
echo DONE
