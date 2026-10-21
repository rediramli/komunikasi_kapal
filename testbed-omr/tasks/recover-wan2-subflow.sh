echo "== revert scheduler to original (uci=blest, live=default)"
uci set network.globals.mptcp_scheduler='blest'; uci commit network
sysctl -w net.mptcp.scheduler=default >/dev/null
echo "uci=$(uci -q get network.globals.mptcp_scheduler) live=$(sysctl -n net.mptcp.scheduler)"
echo
echo "== nudge path manager: re-add wan2 endpoint to force a fresh subflow"
ip mptcp endpoint delete id 57 2>/dev/null
ip mptcp endpoint add 192.168.2.100 dev wan2 subflow fullmesh 2>/dev/null
echo "endpoints now:"; ip mptcp endpoint show
echo
echo "== wait 6s, then check openvpn subflows"
sleep 6
echo "openvpn subflow endpoints:"
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
ss -tnpiM 2>/dev/null | grep -A1 'mptcp.*168.144.105.155' | grep -oE 'subflows:[0-9]+ .*local_addr_used:[0-9]+' | head -1
echo DONE
