echo "scheduler live=$(sysctl -n net.mptcp.scheduler) uci=$(uci -q get network.globals.mptcp_scheduler)"
echo "observing tunnel for ~40s WITHOUT changing anything..."
for k in $(seq 1 8); do
  port=$(ss -tnpM 2>/dev/null | grep openvpn | grep -oE '168.144.105.155:[0-9]+' | head -1)
  nsub=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '168.144.105.155:[0-9]')
  w2=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE 'wan2|192.168.2.100')
  gu=$({ logread 2>/dev/null | grep -c 'ovpn-guard.*restart'; })
  printf "t=%2ds vpsport=%-22s subflow-lines=%s wan2=%s  guard-restarts-total=%s\n" $((k*5)) "$port" "$nsub" "$w2" "$gu"
  sleep 5
done
echo DONE
