echo "scheduler: $(sysctl -n net.mptcp.scheduler)"
echo "sampling per-WAN TX every 3s for ~24s (watch wan2/rutm30 ramp up)"
prev1=$(cat /sys/class/net/wan1/statistics/tx_bytes)
prev2=$(cat /sys/class/net/wan2/statistics/tx_bytes)
for i in 1 2 3 4 5 6 7 8; do
  sleep 3
  c1=$(cat /sys/class/net/wan1/statistics/tx_bytes)
  c2=$(cat /sys/class/net/wan2/statistics/tx_bytes)
  d1=$((c1-prev1)); d2=$((c2-prev2)); prev1=$c1; prev2=$c2
  printf "t=%2ds  wan1(rutm16) +%-9s  wan2(rutm30) +%-9s  (bytes/3s)\n" $((i*3)) "$d1" "$d2"
done
echo DONE
