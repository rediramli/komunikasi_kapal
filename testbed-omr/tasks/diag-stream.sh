echo "== scheduler"; sysctl -n net.mptcp.scheduler
echo "== endpoint (backup?)"; ip mptcp endpoint show
echo "== cut aktif"; nft list tables | grep -E 'twincut|fotest' || echo "tidak ada"
echo "== status OMR"; for w in wan1 wan2; do echo "$w: $(uci -q get openmptcprouter.$w.state)"; done
echo "== tun0"; ip -4 addr show tun0 | grep inet || echo "TIDAK ADA tun0"
echo "== subflow tunnel"; ss -tn | grep ':65301' 
echo "== upload 3 detik"; a=$(cat /sys/class/net/wan1/statistics/tx_bytes); b=$(cat /sys/class/net/wan2/statistics/tx_bytes); sleep 3
echo "Simba $(( ($(cat /sys/class/net/wan1/statistics/tx_bytes)-a)*8/3000 )) kbps, Singtel $(( ($(cat /sys/class/net/wan2/statistics/tx_bytes)-b)*8/3000 )) kbps"
echo "== log terakhir"; logread | grep -E 'omr-twin|ovpn-guard|openvpn' | tail -8
