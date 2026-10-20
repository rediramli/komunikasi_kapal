echo "scheduler=$(sysctl -n net.mptcp.scheduler)  limits: $(ip mptcp limits show | tr '\n' ' ')"
echo
echo "== OpenVPN MPTCP connection + its subflows (per-subflow bytes_sent)"
ss -tnpiM 2>/dev/null | grep -A1 -E 'openvpn' | grep -E '168.144.105.155|bytes_sent' | \
  sed -E 's/.*(192.168.[12].100[^ ]*).*(168.144.105.155:[0-9]+).*/CONN \1 -> \2/; t; s/.*(bytes_sent:[0-9]+).*(tcp-ulp-mptcp.*subflow|flags:[A-Za-z]+).*/   \1/' | head -20
echo
echo "== raw: openvpn subflow endpoints (count tcp lines = subflows)"
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print $4" -> "$5}'
echo
echo "== mptcp-level: subflows_total for openvpn conn"
ss -tnpiM 2>/dev/null | grep -A2 'mptcp.*168.144.105.155' | grep -oE 'subflows_total:[0-9]+|subflows:[0-9]+' | head
echo DONE
