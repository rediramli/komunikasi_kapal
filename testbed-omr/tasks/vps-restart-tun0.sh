echo "== unit for tun0?"
systemctl list-units --type=service 2>/dev/null | grep -iE 'openvpn.*tun0|ovpn.*tun0' | head
echo "== restart openvpn tun0 server"
systemctl restart openvpn@tun0.service 2>&1 || systemctl restart openvpn-tun0.service 2>&1 || echo "(unit name mismatch - check above)"
sleep 2
echo "== server listening again?"
ss -tlnp 2>/dev/null | grep ':65301' | head
echo "== VPS tun0"
ip -br addr show tun0 2>&1
echo DONE
