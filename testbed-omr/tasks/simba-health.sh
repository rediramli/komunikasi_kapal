echo "== scheduler now"; sysctl -n net.mptcp.scheduler
echo "== wan1/Simba: carrier + addr + OMR tracking"
echo "carrier=$(cat /sys/class/net/wan1/carrier 2>/dev/null) addr=$(ip -br addr show wan1|awk '{print $3}')"
echo "wan1 up(ubus)=$(ubus call network.interface.wan1 status 2>/dev/null | jsonfilter -q -e '@.up')"
echo "== can Simba(wan1) reach internet / VPS?"
ping -c3 -W2 -I 192.168.1.100 168.144.105.155 2>&1 | tail -2
echo "== RUTM30 gateway (192.168.1.1) reachable?"
ping -c2 -W2 192.168.1.1 2>&1 | tail -1
echo "== OMR tracking / multipath state for wan1"
uci -q get openmptcprouter.wan1.state; echo " <- openmptcprouter.wan1.state"
logread 2>/dev/null | grep -iE 'wan1|simba|post-tracking.*wan1' | tail -6
echo "== openvpn subflows now"
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo DONE
