uci -q get glorytun.vpn >/dev/null && uci set glorytun.vpn.enable='0'
uci set openmptcprouter.settings.vpn='openvpn'
uci set openvpn.omr.enabled='1'
uci commit glorytun; uci commit openmptcprouter; uci commit openvpn
/etc/init.d/glorytun stop 2>/dev/null; /etc/init.d/openvpn restart; sleep 25
echo "== VPN: $(uci get openmptcprouter.settings.vpn)"
pgrep -af 'glorytun|openvpn' | cut -c1-80
ip -4 addr show tun0 | grep inet || echo "tun0 belum ada IP"
ss -tn | grep ':65301'
