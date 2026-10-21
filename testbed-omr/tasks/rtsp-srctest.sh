H=192.168.110.2
U="rtsp://$H/live/profile.0"
echo "== route BEFORE"
ip route get $H | head -1
echo
echo "== set preferred src to in-subnet 192.168.110.250"
ip route replace 192.168.110.0/24 dev eth0 src 192.168.110.250
ip route get $H | head -1
echo
echo "== DESCRIBE (no auth) from in-subnet src"
printf "DESCRIBE $U RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,15p'
echo "---- end ----"
echo
echo "== restore preferred src to 192.168.100.1"
ip route replace 192.168.110.0/24 dev eth0 src 192.168.100.1
ip route get $H | head -1
echo DONE
