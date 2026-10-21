L=$(uci -q get glorytun-udp.vpn.localip); R=$(uci -q get glorytun-udp.vpn.remoteip)
echo "uci: local=$L remote=$R"
[ -z "$L" ] && { uci show glorytun-udp | head -20; exit 1; }
ip -4 addr show tun0 | grep -q "$L" || ip addr add $L peer $R dev tun0
ip link set tun0 up; ifup omrvpn 2>/dev/null; sleep 3
ip -br addr show tun0
ping -c3 -W2 $R | tail -1
