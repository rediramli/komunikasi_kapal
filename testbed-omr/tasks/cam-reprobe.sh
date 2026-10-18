H=192.168.110.2
echo "== ping $H"
ping -c2 -W2 $H 2>&1 | tail -2
echo "== ARP $H"
ping -c1 -W1 $H >/dev/null 2>&1; ip neigh | grep "$H" || echo "(no neigh)"
echo
echo "== OPTIONS"
printf "OPTIONS rtsp://$H/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,8p'
echo "---- end ----"
echo
echo "== DESCRIBE no-auth (want 401 now, not 454)"
printf "DESCRIBE rtsp://$H/live/profile.0 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,15p'
echo "---- end ----"
echo DONE
