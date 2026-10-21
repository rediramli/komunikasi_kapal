echo "before: multiqueue=$(uci -q get glorytun.vpn.multiqueue) cpu_affinity=$(uci -q get glorytun.vpn.cpu_affinity)"
uci set glorytun.vpn.multiqueue='0'
uci set glorytun.vpn.cpu_affinity='0'
uci commit glorytun
/etc/init.d/glorytun stop 2>/dev/null; sleep 1; ip link del tun0 2>/dev/null; sleep 1
/etc/init.d/glorytun start 2>&1 | grep -iE 'error|duplicate|garbage' || echo "start clean"
for i in $(seq 1 16); do
  sleep 3
  ip -br addr show tun0 2>/dev/null | grep -q '10.255.255.2' && { echo "IP up at ${i}x3s"; break; }
done
echo "tun0: $(ip -br addr show tun0 2>&1)"
echo "ping 10.255.255.1: $(ping -c2 -W2 10.255.255.1 2>&1 | tail -1)"
echo "camera route: $(ip route | grep -E '192.168.100.0' | head -1)"
echo "omr.vpn=$(uci -q get openmptcprouter.omr.vpn)  subflows=$(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)"
echo DONE
