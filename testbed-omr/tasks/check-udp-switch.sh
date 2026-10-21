echo "vpn=$(uci -q get openmptcprouter.settings.vpn) tun0=$(ip -br addr show tun0|awk '{print $3}')"
echo "glorytun-udp enable=$(uci -q get glorytun-udp.vpn.enable) glorytun enable=$(uci -q get glorytun.vpn.enable)"
echo "glorytun-udp proc: $(pgrep -af glorytun-udp | head -1 | cut -c1-70)"
echo "ping VPS 10.255.254.1: $(ping -c2 -W2 10.255.254.1 2>&1 | tail -1)"
echo "omr.vpn=$(uci -q get openmptcprouter.omr.vpn)"
echo DONE
