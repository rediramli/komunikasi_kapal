/etc/init.d/glorytun stop 2>/dev/null; sleep 1
ip link del tun0 2>/dev/null && echo "removed tun0"
sleep 1
/etc/init.d/glorytun start 2>&1 | grep -iE 'error|duplicate' || echo "start: no error"
for i in $(seq 1 15); do
  sleep 3
  a=$(ip -br addr show tun0 2>/dev/null | grep -oE '10.255.255.2')
  [ -n "$a" ] && { echo "tun0 has IP at ${i}x3s"; break; }
done
echo "tun0: $(ip -br addr show tun0 2>&1)"
echo "ping VPS 10.255.255.1: $(ping -c2 -W2 10.255.255.1 2>&1 | tail -1)"
echo "route to camera LAN: $(ip route get 192.168.100.1 2>&1 | head -1)"
echo "MPTCP subflows: $(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)"
echo DONE
