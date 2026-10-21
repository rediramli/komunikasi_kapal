OLD=$(sysctl -n net.mptcp.scheduler 2>/dev/null)
echo "scheduler BEFORE: $OLD"
echo "uci persistent:   $(uci -q get network.globals.mptcp_scheduler)"
echo "available:        $(sysctl -n net.mptcp.available_schedulers 2>/dev/null)"
echo
echo "== setting live scheduler -> default (aggregating), reversible, not persisted"
sysctl -w net.mptcp.scheduler=default
echo "scheduler NOW: $(sysctl -n net.mptcp.scheduler)"
echo
echo "== load test: 25s download via tunnel, measure per-WAN delta"
rd(){ cat /sys/class/net/$1/statistics/rx_bytes; }; td(){ cat /sys/class/net/$1/statistics/tx_bytes; }
a1r=$(rd wan1);a1t=$(td wan1);a2r=$(rd wan2);a2t=$(td wan2)
timeout 25 curl -s -o /dev/null https://speed.cloudflare.com/__down?bytes=500000000 2>/dev/null
sleep 1
b1r=$(rd wan1);b1t=$(td wan1);b2r=$(rd wan2);b2t=$(td wan2)
printf "wan1 (rutm16)  rx=+%-10s tx=+%s\n" $((b1r-a1r)) $((b1t-a1t))
printf "wan2 (rutm30)  rx=+%-10s tx=+%s\n" $((b2r-a2r)) $((b2t-a2t))
echo
echo "== subflow totals now"
ss -tiM 2>/dev/null | grep -oE 'subflows_total:[0-9]+' | sort | uniq -c
echo DONE
