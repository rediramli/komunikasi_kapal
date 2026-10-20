p1=$(cat /sys/class/net/wan1/statistics/tx_bytes); p2=$(cat /sys/class/net/wan2/statistics/tx_bytes)
echo "sched=$(sysctl -n net.mptcp.scheduler); watching subflow + per-WAN TX during stream"
for i in $(seq 1 10); do
  sleep 4
  c1=$(cat /sys/class/net/wan1/statistics/tx_bytes); c2=$(cat /sys/class/net/wan2/statistics/tx_bytes)
  w2sf=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE 'wan2|192.168.2.100')
  printf "t=%2ds wan1 +%-9s wan2 +%-9s  wan2-subflow=%s\n" $((i*4)) $((c1-p1)) $((c2-p2)) "$w2sf"
  p1=$c1; p2=$c2
done
echo DONE
