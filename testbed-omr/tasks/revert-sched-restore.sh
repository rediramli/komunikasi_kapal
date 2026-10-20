echo "== revert scheduler: live=default, uci=blest (original)"
sysctl -w net.mptcp.scheduler=default >/dev/null
uci set network.globals.mptcp_scheduler='blest'; uci commit network
echo "live=$(sysctl -n net.mptcp.scheduler) uci=$(uci -q get network.globals.mptcp_scheduler)"
echo "== wait up to 40s for tun0 to come up (watchdog will re-establish under default)"
for i in $(seq 1 20); do
  sleep 2
  if ip -br addr show tun0 2>/dev/null | grep -q 10.255.252.2; then echo "tun0 UP after ~$((i*2))s"; break; fi
done
ip -br addr show tun0 2>&1
echo "== recent openvpn result lines"
logread 2>/dev/null | grep -iE 'openvpn|post-tracking' | tail -8 | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
