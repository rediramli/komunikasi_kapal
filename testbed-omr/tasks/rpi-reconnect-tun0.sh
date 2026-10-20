echo "sched=$(sysctl -n net.mptcp.scheduler)"
echo "tun0 before: $(ip -br addr show tun0 2>/dev/null || echo DOWN)"
echo "== clean openvpn restart against healthy VPS server"
setsid sh -c '/etc/init.d/openvpn restart' >/tmp/ovpn-rc.log 2>&1 </dev/null &
for k in $(seq 1 24); do
  sleep 3
  if ip -br addr show tun0 2>/dev/null | grep -q 10.255.252.2; then echo "tun0 UP after ~$((k*3))s"; break; fi
done
ip -br addr show tun0 2>&1
echo "== handshake result"
logread 2>/dev/null | grep -iE 'openvpn.*(Initialization Sequence Completed|Peer Connection Initiated)' | tail -2 | sed 's/admin:[^@]*@/admin:***@/'
echo "== ping VPS tunnel end"
ping -c2 -W2 10.255.252.1 2>&1 | tail -1
echo DONE
