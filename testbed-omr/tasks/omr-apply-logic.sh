echo "== openvpn.omr enable key + current"
uci show openvpn.omr 2>/dev/null | grep -iE 'enable' | head
echo "== how omr enables/disables VPNs by settings.vpn (grep init)"
grep -nE "available_vpn|settings.vpn|\.enable=|enable '1'|enable='1'|glorytun_udp|openvpn_bonding" /etc/init.d/openmptcprouter 2>/dev/null | head -25
echo "== restart hooks: what 'openmptcprouter' start does for vpn"
sed -n '70,140p' /etc/init.d/openmptcprouter 2>/dev/null | grep -nE 'vpn|glorytun|openvpn|enable|/etc/init.d' | head -25
echo "== is there an omr wizard / vps reconf trigger?"
grep -rnE 'service_vpn|_set_glorytun_vps|_set_openvpn_vps|reload_vpn|vps.*restart' /etc/init.d/openmptcprouter-vps 2>/dev/null | head -10
echo DONE
