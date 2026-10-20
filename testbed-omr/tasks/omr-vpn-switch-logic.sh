echo "== how settings.vpn is consumed (openmptcprouter init)"
grep -nE 'settings.vpn|current_vpn|glorytun|openvpn' /etc/init.d/openmptcprouter 2>/dev/null | head -30
echo
echo "== does router push vpn choice to VPS? (omr-admin API calls)"
grep -nE 'vpn|65500|/vpn|set_vpn|service=' /etc/init.d/openmptcprouter-vps 2>/dev/null | grep -iE 'vpn' | head -20
echo DONE
