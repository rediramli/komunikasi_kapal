for k in 1 2 3; do
  sf=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '168.144.105.155:[0-9]')
  w2=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE 'wan2|192.168.2.100')
  echo "t$k: openvpn tcp lines=$sf  wan2-subflow-lines=$w2  sched=$(sysctl -n net.mptcp.scheduler)"
  sleep 3
done
