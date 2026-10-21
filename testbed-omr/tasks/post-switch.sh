MAC=88:76:b9:f9:6a:04; IP=192.168.100.20
uci -q delete dhcp.dlinkcam
uci set dhcp.dlinkcam=host
uci set dhcp.dlinkcam.name='dlink-cam'
uci set dhcp.dlinkcam.mac="$MAC"
uci set dhcp.dlinkcam.ip="$IP"
uci commit dhcp && /etc/init.d/dnsmasq restart
sed -i "s/192\.168\.110\.2\b/$IP/g" /etc/dlink/*.nft
/etc/init.d/firewall reload >/dev/null 2>&1
echo "== aturan DNAT"; nft list ruleset | grep -n "$IP"
echo "== lease kamera"; grep -i "$MAC" /tmp/dhcp.leases || echo "(belum ada - restart kamera lagi)"
echo "== kamera"; ping -c2 -W1 $IP >/dev/null && echo "ping OK" || echo "ping GAGAL"
nc -z -w2 $IP 554 && echo "RTSP 554 OK" || echo "RTSP 554 belum"
echo "== tunnel"; ss -tn | grep ':65301'
