echo "settings.vpn=$(uci -q get openmptcprouter.settings.vpn)"
echo "camera tunnel tun0=$(ip -br addr show tun0|awk '{print $3}') (10.255.255.x=glorytun-TCP/MPTCP)"
echo "glorytun MPTCP subflows=$(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1)"
echo DONE
