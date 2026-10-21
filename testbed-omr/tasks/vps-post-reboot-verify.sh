echo "== VPS uptime (fresh?)"
uptime
echo "== openvpn@tun0 server"
systemctl is-active openvpn@tun0.service 2>/dev/null
ss -tlnp 2>/dev/null | grep ':65301' | head -1 || echo "(not listening yet)"
echo "== no wedged D-state openvpn?"
ps -eo pid,stat,cmd | grep -E 'openvpn.*tun0' | grep -v grep | head
echo "== mediamtx"
systemctl is-active mediamtx 2>/dev/null
echo "== VPS tun0 iface"
ip -br addr show tun0 2>&1 | head -1
echo DONE
