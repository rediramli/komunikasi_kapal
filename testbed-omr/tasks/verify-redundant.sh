echo "scheduler: live=$(sysctl -n net.mptcp.scheduler) uci=$(uci -q get network.globals.mptcp_scheduler)"
echo
echo "== openvpn subflows (both WANs present & stable?)"
for k in 1 2 3; do
  echo "- sample $k:"
  ss -tnpiM 2>/dev/null | grep -E 'openvpn' | grep -E '168.144.105.155' | \
    awk '{print "   "$4" -> "$5}'
  sleep 2
done
echo
echo "== per-subflow bytes_sent (wan2 actively sending?)"
ss -tnpiM 2>/dev/null | grep -A1 openvpn | grep -oE '(192.168.[12].100[^ ]*|bytes_sent:[0-9]+)' | paste - - 2>/dev/null | head
echo DONE
