for i in $(seq 1 12); do
  ip -br addr show tun0 2>/dev/null | grep -q '10.255.255.2' && break
  sleep 2
done
echo "tun0: $(ip -br addr show tun0 2>&1)"
echo "sched live: $(sysctl -n net.mptcp.scheduler)"
echo "glorytun MPTCP subflows: $(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)"
echo DONE
