echo "settings.vpn=$(uci -q get openmptcprouter.settings.vpn)"
echo "glorytun(tcp).enable=$(uci -q get glorytun.vpn.enable) mptcp=$(uci -q get glorytun.vpn.mptcp)  glorytun-udp.enable=$(uci -q get glorytun-udp.vpn.enable)"
echo "wait for tunnel iface 10.255.255.x (glorytun TCP)..."
for i in $(seq 1 18); do
  sleep 3
  t=$(ip -br addr | grep -E '10.255.255')
  [ -n "$t" ] && { echo "up at ${i}x3s: $t"; break; }
done
ip -br addr | grep -iE 'tun|gt-|10.255' | head
echo "== glorytun TCP process + its MPTCP connection to VPS"
pgrep -af 'glorytun ' | grep -iv udp | head -1
echo "-- MPTCP for glorytun conn (subflows across WANs?):"
ss -tnpiM 2>/dev/null | grep -A1 glorytun | grep -oE 'subflows_total:[0-9]+|192.168.[12].100' | head
ss -tnpM 2>/dev/null | grep -i glorytun | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo "omr.vpn=$(uci -q get openmptcprouter.omr.vpn)"
echo DONE
