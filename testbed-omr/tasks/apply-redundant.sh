echo "== 1. persist + live bpf_red"
uci set network.globals.mptcp_scheduler='bpf_red'; uci commit network
sysctl -w net.mptcp.scheduler=bpf_red >/dev/null
echo "uci=$(uci -q get network.globals.mptcp_scheduler) live=$(sysctl -n net.mptcp.scheduler)"
echo
echo "== 2. restart openvpn so its MPTCP conn is created under bpf_red"
setsid sh -c '/etc/init.d/openvpn restart' >/tmp/ovpn-restart2.log 2>&1 </dev/null &
for i in $(seq 1 30); do sleep 1; ip -br addr show tun0 2>/dev/null | grep -q '10.255.252.2' && { echo "tun0 up after ${i}s"; break; }; done
sleep 2
echo
echo "== 3. nudge wan2 subflow onto the new connection"
id=$(ip mptcp endpoint show | awk '/dev wan2/{print $3}')
[ -n "$id" ] && ip mptcp endpoint delete id "$id"
ip mptcp endpoint add 192.168.2.100 dev wan2 subflow fullmesh 2>/dev/null
echo "endpoints:"; ip mptcp endpoint show
echo
echo "== 4. wait 6s, show openvpn subflows"
sleep 6
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo DONE
