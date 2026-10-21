for k in 1 2 3; do
  line=$(ss -tnpiM 2>/dev/null | grep -A2 'mptcp.*168.144.105.155' | grep -E 'subflows:' | head -1)
  sf=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '168.144.105.155')
  port=$(ss -tnpM 2>/dev/null | grep openvpn | grep -oE '168.144.105.155:[0-9]+' | head -1)
  echo "t$k: openvpn tcp subflow-lines=$sf  vps=$port  [$line]"
  sleep 3
done
echo
echo "== endpoints + limits"
ip mptcp endpoint show
echo "== is wan2 subflow present for openvpn?"
ss -tnpM 2>/dev/null | grep openvpn | grep -E 'wan2|192.168.2.100' && echo "wan2 subflow: YES" || echo "wan2 subflow: NO"
echo DONE
