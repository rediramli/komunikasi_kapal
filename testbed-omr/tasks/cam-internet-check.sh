echo "== reach camera + Ruijie LAN gw"
ping -c2 -W2 192.168.110.2 2>&1 | tail -2
ping -c2 -W2 192.168.110.1 2>&1 | tail -2
echo
echo "== RPi own internet (via MPTCP uplinks)"
ping -c2 -W2 8.8.8.8 2>&1 | tail -2
echo
echo "== Ruijie WAN addr 192.168.100.203 reachable from RPi?"
ping -c2 -W2 192.168.100.203 2>&1 | tail -2
echo
echo "== conntrack: outbound flows sourced from Ruijie WAN (192.168.100.203)"
echo "   (if Ruijie LAN has internet through us, external dst IPs appear here)"
grep '192.168.100.203' /proc/net/nf_conntrack 2>/dev/null | grep -vE 'dst=192\.168\.|dst=10\.' | head -15
echo "-- count of such external flows:"
grep -c '192.168.100.203' /proc/net/nf_conntrack 2>/dev/null
echo
echo "== any conntrack mentioning camera 192.168.110.2 (direct, non-NAT)"
grep '192.168.110.2' /proc/net/nf_conntrack 2>/dev/null | head -8
echo DONE
