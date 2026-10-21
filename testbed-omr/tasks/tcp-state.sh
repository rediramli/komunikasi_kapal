echo "tun0=$(ip -br addr show tun0 2>&1) subflows=$(ss -tniM 2>/dev/null | grep ':65001' -A1 | grep -oE 'subflows_total:[0-9]+' | head -1) omr.vpn=$(uci -q get openmptcprouter.omr.vpn)"
