echo "== delete stale tun0, restart glorytun TCP"
ip link del tun0 2>/dev/null && echo "deleted stale tun0" || echo "(no tun0 to delete)"
/etc/init.d/glorytun restart 2>&1 | tail -3
echo "== wait for tun0 up (10.255.255.2)"
for i in $(seq 1 15); do
  sleep 3
  ip -br addr show tun0 2>/dev/null | grep -q '10.255.255.2' && ip -br addr show tun0 | grep -qv DOWN && { echo "tun0 UP at ${i}x3s: $(ip -br addr show tun0)"; break; }
done
ip -br addr show tun0 2>&1
echo "ping VPS tunnel 10.255.255.1: $(ping -c2 -W2 10.255.255.1 2>&1 | tail -1)"
echo "glorytun proc: $(pgrep -af glorytun | head -1)"
echo "== MPTCP on glorytun conn (subflows across WANs):"
ss -tnpiM 2>/dev/null | grep -A1 ':65001' | grep -oE 'subflows_total:[0-9]+|tcp-ulp-mptcp' | head
ss -tnpM 2>/dev/null | grep ':65001' | awk '{print "  "$4" -> "$5}'
echo DONE
