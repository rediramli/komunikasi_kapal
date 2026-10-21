echo "sched=$(sysctl -n net.mptcp.scheduler)"
echo "== clean openvpn restart (detached)"
setsid sh -c '/etc/init.d/openvpn restart' >/tmp/ovpn-r.log 2>&1 </dev/null &
for k in $(seq 1 18); do
  sleep 3
  if ip -br addr show tun0 2>/dev/null | grep -q 10.255.252.2; then echo "tun0 UP after ~$((k*3))s"; break; fi
done
ip -br addr show tun0 2>&1
echo "== last openvpn lines"
logread 2>/dev/null | grep -iE 'openvpn.*(Initialization|Peer Connection Initiated|TLS Error|AUTH|VERIFY)' | tail -5 | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
