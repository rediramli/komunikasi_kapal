for k in 1 2 3 4 5 6; do
  if ip -br addr show tun0 2>/dev/null | grep -q 10.255.252.2; then
    echo "tun0 UP: $(ip -br addr show tun0)"
    echo "ping VPS tunnel end:"; ping -c2 -W2 10.255.252.1 2>&1 | tail -1
    break
  fi
  echo "t$k: tun0 not up yet"; sleep 4
done
logread 2>/dev/null | grep -iE 'openvpn.*Initialization|Peer Connection|post-tracking' | tail -4 | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
