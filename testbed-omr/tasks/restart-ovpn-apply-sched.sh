echo "scheduler live=$(sysctl -n net.mptcp.scheduler) uci=$(uci -q get network.globals.mptcp_scheduler)"
echo "openvpn MPTCP conn BEFORE:"; ss -tnpM 2>/dev/null | grep -E '168.144.105.155' | grep openvpn | head
echo "== restarting openvpn (detached so it finishes even if ssh blips)"
setsid sh -c '/etc/init.d/openvpn restart' >/tmp/ovpn-restart.log 2>&1 </dev/null &
# wait for tun0 to come back up
for i in $(seq 1 30); do
  sleep 1
  ip -br addr show tun0 2>/dev/null | grep -q '10.255.252.2' && { echo "tun0 up after ${i}s"; break; }
done
ip -br addr show tun0
echo "openvpn MPTCP conn AFTER:"; ss -tnpM 2>/dev/null | grep -E '168.144.105.155' | grep openvpn | head
echo DONE
