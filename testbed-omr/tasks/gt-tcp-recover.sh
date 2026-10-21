sysctl -w net.mptcp.scheduler=default >/dev/null
/etc/init.d/glorytun stop 2>/dev/null; sleep 1; ip link del tun0 2>/dev/null; sleep 1
/etc/init.d/glorytun start >/dev/null 2>&1
# wait for tun0 device then assign IP
for i in $(seq 1 20); do ip link show tun0 >/dev/null 2>&1 && break; sleep 2; done
sleep 2
ip addr show tun0 | grep -q 10.255.255.2 || ip addr add 10.255.255.2/32 peer 10.255.255.1 dev tun0 2>/dev/null
ip link set tun0 up
# wait for 2 subflows
for i in $(seq 1 12); do
  n=$(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)
  echo "$n" | grep -q 'subflows_total:2' && break
  sleep 2
done
echo "sched=$(sysctl -n net.mptcp.scheduler) tun0=$(ip -br addr show tun0|awk '{print $3}') subflows=$(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)"
echo "ping VPS: $(ping -c2 -W2 10.255.255.1 2>&1 | tail -1)"
echo DONE
