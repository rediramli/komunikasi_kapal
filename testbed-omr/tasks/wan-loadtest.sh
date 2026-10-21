rd() { cat /sys/class/net/$1/statistics/rx_bytes; }
td() { cat /sys/class/net/$1/statistics/tx_bytes; }
w1r0=$(rd wan1); w1t0=$(td wan1); w2r0=$(rd wan2); w2t0=$(td wan2)
echo "generating ~10s of download traffic through the OMR tunnel..."
# download exits via VPS -> fills subflows; cap time, discard data
timeout 10 curl -s -o /dev/null https://speed.cloudflare.com/__down?bytes=200000000 2>/dev/null
sleep 1
w1r1=$(rd wan1); w1t1=$(td wan1); w2r1=$(rd wan2); w2t1=$(td wan2)
echo "== per-WAN delta bytes over the test =="
printf "wan1 (rutm16?)  rx=+%s  tx=+%s\n" $((w1r1-w1r0)) $((w1t1-w1t0))
printf "wan2 (rutm30?)  rx=+%s  tx=+%s\n" $((w2r1-w2r0)) $((w2t1-w2t0))
echo
echo "== scheduler / packet sched in use"
sysctl net.mptcp 2>/dev/null | grep -iE 'scheduler|checksum|path' || cat /proc/sys/net/mptcp/* 2>/dev/null | head
uci -q get openmptcprouter.settings.mptcp_scheduler; echo " <- omr scheduler setting"
echo DONE
