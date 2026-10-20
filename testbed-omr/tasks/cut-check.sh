echo "== nft tables (twincut / fotest present?)"
nft list tables 2>/dev/null | grep -iE 'twincut|fotest' || echo "(no cut tables)"
echo "== per-WAN tx delta over 4s (is wan1/Simba still sending?)"
r(){ cat /sys/class/net/$1/statistics/tx_bytes; }
a1=$(r wan1); a2=$(r wan2); sleep 4; b1=$(r wan1); b2=$(r wan2)
echo "wan1/Simba +$(( (b1-a1)*8/1000/4 )) kbps   wan2/Singtel +$(( (b2-a2)*8/1000/4 )) kbps"
echo "== openvpn subflows"
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo DONE
