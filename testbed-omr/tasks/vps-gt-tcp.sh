echo "glorytun-tcp service: $(systemctl is-active glorytun-tcp@tun0 2>/dev/null)"
ss -tlnp 2>/dev/null | grep ':65001' | head || echo "(nothing on 65001)"
ip -br addr | grep -iE 'gt-tun0|10.255.255' | head
pgrep -af 'glorytun' | grep -i tcp | head -1
echo DONE
