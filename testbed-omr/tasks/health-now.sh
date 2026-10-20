echo "== tun0"; ip -br addr show tun0 2>/dev/null || echo "tun0 DOWN"
echo "== ping VPS tunnel end"; ping -c2 -W2 10.255.252.1 2>&1 | tail -1
echo "== openvpn subflows"; ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo "== any cut table still active? (twincut/fotest)"; nft list tables 2>/dev/null | grep -iE 'twincut|fotest' || echo "(no cut tables - good)"
echo "== scheduler"; sysctl -n net.mptcp.scheduler
echo "== per-WAN tx now (4s)"; r(){ cat /sys/class/net/$1/statistics/tx_bytes; }; a1=$(r wan1);a2=$(r wan2);sleep 4;b1=$(r wan1);b2=$(r wan2); echo "wan1 +$(((b1-a1)*8/1000/4))kbps wan2 +$(((b2-a2)*8/1000/4))kbps"
echo DONE
