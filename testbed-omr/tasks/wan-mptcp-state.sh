echo "== WAN link carrier + addr (wan1, wan2)"
for w in wan1 wan2; do
  echo "-- $w"
  ip -br addr show dev $w 2>/dev/null
  cat /sys/class/net/$w/carrier 2>/dev/null | sed 's/^/carrier=/'
done
echo
echo "== default routes / mwan"
ip route show | grep -E 'default|192.168.1.|192.168.2.' | head
echo
echo "== uci network wan1/wan2 (auto, disabled)"
for s in wan1 wan2; do
  echo "-- $s: auto=$(uci -q get network.$s.auto) disabled=$(uci -q get network.$s.disabled) proto=$(uci -q get network.$s.proto)"
done
echo
echo "== MPTCP endpoints"
ip mptcp endpoint show 2>/dev/null
echo
echo "== MPTCP connections to VPS: subflow count per conn"
ss -tiM 2>/dev/null | grep -E 'mptcp|subflows_total' | head -20
echo
echo "== per-WAN tx/rx bytes (traffic flowing?)"
for w in wan1 wan2; do
  r=$(cat /sys/class/net/$w/statistics/rx_bytes 2>/dev/null)
  t=$(cat /sys/class/net/$w/statistics/tx_bytes 2>/dev/null)
  echo "$w rx=$r tx=$t"
done
echo DONE
