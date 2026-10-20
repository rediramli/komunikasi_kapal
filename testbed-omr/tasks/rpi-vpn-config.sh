echo "== OMR Default VPN / proxy settings"
echo "vpn=$(uci -q get openmptcprouter.settings.vpn)  proxy=$(uci -q get openmptcprouter.settings.proxy)"
echo
echo "== glorytun uci config (udp/tcp)"
uci show glorytun 2>/dev/null | grep -iE 'enable|host|port|key|dev|localip|remoteip|proto|mptcp' | sed 's/key=.*/key=***/' | head -30
echo
echo "== tunnel interfaces present now"
ip -br addr | grep -iE 'tun|gt-|glory|10.255' | head
echo
echo "== which VPN services enabled on RPi"
for s in openvpn glorytun glorytun-udp; do [ -x /etc/init.d/$s ] && echo "$s enabled=$(/etc/init.d/$s enabled 2>/dev/null && echo yes || echo no)"; done
echo
echo "== how LAN (192.168.100.0/24) + camera routed from VPS side is set: RPi routes"
ip route | grep -E '10.255|default' | head
echo DONE
