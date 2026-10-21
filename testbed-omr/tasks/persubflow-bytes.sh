echo "sched=$(sysctl -n net.mptcp.scheduler)"
echo "sampling openvpn per-subflow bytes_sent twice (10s apart) during stream"
snap() {
  ss -tnipM 2>/dev/null | grep -A1 openvpn | awk '
    /168\.144\.105\.155/ { split($4,a,"%"); split(a[1],b,":"); src=b[1]; next }
    /bytes_sent/ { for(i=1;i<=NF;i++) if($i ~ /^bytes_sent:/){ sub("bytes_sent:","",$i); print src"  "$i } }'
}
echo "-- snap1 --"; snap
sleep 10
echo "-- snap2 --"; snap
echo DONE
