H=192.168.100.134
echo "== ping camera on RPi LAN ($H)"
ping -c2 -W2 $H 2>&1 | tail -2
echo
echo "== ARP/MAC for $H (expect 8876b9f96a04)"
ping -c1 -W1 $H >/dev/null 2>&1; ip neigh | grep "$H" || echo "(no neigh)"
echo
echo "== RTSP OPTIONS to $H:554"
printf "OPTIONS rtsp://$H/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,8p'
echo "---- end ----"
echo
echo "== RTSP DESCRIBE (no auth) to $H:554 (expect 454 until ONVIF on)"
printf "DESCRIBE rtsp://$H/live/profile.0 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,10p'
echo "---- end ----"
echo DONE
