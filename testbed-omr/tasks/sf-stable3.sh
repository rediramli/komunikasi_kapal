for k in 1 2 3; do
  si=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '192.168.1.100')
  sg=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '192.168.2.100|wan2')
  echo "t$k: simba-subflow-lines=$si singtel-subflow-lines=$sg sched=$(sysctl -n net.mptcp.scheduler)"
  sleep 3
done
