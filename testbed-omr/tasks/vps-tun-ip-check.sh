echo "== RPi client IP in openvpn status"
grep -iE '10.255.252|CLIENT_LIST|ROUTING' /run/openvpn/tun0.status 2>/dev/null | head
echo "== VPS route to camera subnet 192.168.100.0/24 / 192.168.110.0/24"
ip route | grep -E '192.168.100|192.168.110|10.255.252' | head
echo "== mediamtx dlink source (masked)"
grep -nE 'source:.*10.255.252' /etc/mediamtx/mediamtx.yml | sed 's/admin:[^@]*@/admin:***@/'
echo "== can VPS reach RPi tunnel .2 vs .3?"
ping -c2 -W2 10.255.252.2 2>&1 | tail -1 | sed 's/^/.2: /'
ping -c2 -W2 10.255.252.3 2>&1 | tail -1 | sed 's/^/.3: /'
echo "== can VPS reach camera via tunnel (OPTIONS to 10.255.252.X:18554)"
for ip in 10.255.252.2 10.255.252.3; do printf "OPTIONS rtsp://$ip:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 4 nc $ip 18554 2>/dev/null | head -1 | sed "s|^|$ip -> |"; done
echo DONE
