echo "== Default VPN & proxy"
echo "vpn=$(uci -q get openmptcprouter.settings.vpn)  proxy=$(uci -q get openmptcprouter.settings.proxy)"
echo
echo "== kernel MPTCP connections (which process uses MPTCP across WANs)"
ss -tnpiM 2>/dev/null | grep -E 'mptcp|users:' | grep -oE 'users:\(\("[^"]+' | sed 's/.*"//' | sort | uniq -c
echo "-- subflow counts on MPTCP conns:"
ss -tniM 2>/dev/null | grep -oE 'subflows_total:[0-9]+' | sort | uniq -c
echo
echo "== camera tunnel = glorytun (UDP, non-MPTCP)?"
echo "tun0: $(ip -br addr show tun0 | awk '{print $3}')  (10.255.254.x = glorytun-udp)"
pgrep -af 'glorytun-udp' | head -1
echo
echo "== does glorytun process use MPTCP? (it's UDP, so no)"
ss -unp 2>/dev/null | grep -i glory | head -2 || echo "(glorytun is UDP - not a TCP/MPTCP socket)"
echo DONE
