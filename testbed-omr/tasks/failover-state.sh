echo "== wan carriers (wan1=Simba/RUTM30, wan2=Singtel/RUTM16)"
for w in wan1 wan2; do echo "$w carrier=$(cat /sys/class/net/$w/carrier 2>/dev/null) addr=$(ip -br addr show $w 2>/dev/null | awk '{print $3}')"; done
echo "== tun0"
ip -br addr show tun0 2>/dev/null || echo "tun0 DOWN"
echo "== default routes"
ip route show default | head
echo "== openvpn subflows to VPS"
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo "== ping VPS tunnel end via tun0"
ping -c2 -W2 10.255.252.1 2>&1 | tail -1
echo "== ping VPS public from wan2 (Singtel still works?)"
ping -c2 -W2 -I 192.168.2.100 168.144.105.155 2>&1 | tail -1
echo DONE
