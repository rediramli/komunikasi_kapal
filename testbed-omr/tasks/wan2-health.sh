V=168.144.105.155
echo "== gateways reachable?"
ping -c2 -W2 192.168.1.1 2>&1 | tail -1
ping -c2 -W2 192.168.2.1 2>&1 | tail -1
echo
echo "== VPS reachable sourced from each WAN"
echo "-- from wan1 (192.168.1.100 / rutm16):"
ping -c3 -W2 -I 192.168.1.100 $V 2>&1 | tail -2
echo "-- from wan2 (192.168.2.100 / rutm30):"
ping -c3 -W2 -I 192.168.2.100 $V 2>&1 | tail -2
echo
echo "== TCP to VPS:65301 sourced from wan2 (can a subflow even connect?)"
timeout 5 sh -c 'echo > /dev/tcp/168.144.105.155/65301' 2>&1 && echo "wan2 default-route TCP ok" || echo "(bash /dev/tcp not available in sh)"
echo
echo "== wan2 link errors/drops"
ip -s link show wan2 | sed -n '3,6p'
echo
echo "== mwan/track state if present"
for i in wan1 wan2; do echo "$i: $(ubus call network.interface.$i status 2>/dev/null | jsonfilter -q -e '@.up') up"; done
echo DONE
