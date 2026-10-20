echo "omr.vpn status: $(uci -q get openmptcprouter.omr.vpn)"
echo "glorytun-udp proc: $(pgrep -af glorytun-udp | head -1)"
r(){ cat /sys/class/net/$1/statistics/tx_bytes; }
a1=$(r wan1);a2=$(r wan2); sleep 8; b1=$(r wan1);b2=$(r wan2)
echo "over 8s: wan1/Simba +$(((b1-a1)*8/1000/8))kbps  wan2/Singtel +$(((b2-a2)*8/1000/8))kbps"
echo "ping VPS tunnel: $(ping -c2 -W2 10.255.254.1 2>&1 | tail -1)"
echo DONE
