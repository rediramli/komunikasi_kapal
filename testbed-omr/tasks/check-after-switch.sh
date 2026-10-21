echo "== router"; ping -c2 -W1 -I wan1 192.168.1.1 >/dev/null && echo "RUTM30 OK" || echo "RUTM30 GAGAL"
ping -c2 -W1 -I wan2 192.168.2.1 >/dev/null && echo "RUTM16 OK" || echo "RUTM16 GAGAL"
for w in wan1 wan2; do echo "$w OMR: $(uci -q get openmptcprouter.$w.state)"; done
echo "== tunnel"; ip -4 addr show tun0 | grep inet || echo "tun0 TIDAK ADA"; ss -tn | grep ':65301'
logread | grep openvpn | tail -4
echo "== kamera"; grep -i 88:76:b9 /tmp/dhcp.leases
for ip in 192.168.100.20 192.168.100.134; do ping -c1 -W1 $ip >/dev/null && echo "$ip hidup"; done
nc -z -w2 192.168.100.20 554 && echo "RTSP .20 OK"
