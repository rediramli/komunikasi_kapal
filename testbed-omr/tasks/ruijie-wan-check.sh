echo "== neighbor/ARP table on 192.168.100.0/24 (is Ruijie WAN .203 present?)"
ip neigh show dev eth0 | grep -E '192\.168\.100\.' | head
echo "-- specifically .203:"
ip neigh show 192.168.100.203 2>/dev/null; ip neigh | grep '192.168.100.203' || echo "(no neighbor entry for .203)"
echo
echo "== DHCP leases handed out by RPi (look for Ruijie / camera)"
for L in /tmp/dhcp.leases /var/dhcp.leases /tmp/dnsmasq.leases; do
  [ -f "$L" ] && { echo "-- $L"; cat "$L"; }
done
echo
echo "== who is on 192.168.100.x right now (neigh full)"
ip -br neigh | grep '192.168.100' | head
echo
echo "== try ARP-force: ping .203 then show neigh"
ping -c1 -W1 192.168.100.203 >/dev/null 2>&1; ip neigh | grep '192.168.100.203' || echo "(still no ARP for .203 -> not on this L2)"
echo DONE
