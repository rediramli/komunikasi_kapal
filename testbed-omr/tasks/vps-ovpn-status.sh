echo "== openvpn@tun0 service state"
systemctl is-active openvpn@tun0.service 2>/dev/null
echo "== listening on 65301?"
ss -tlnp 2>/dev/null | grep ':65301' || echo "NOT LISTENING on 65301!"
echo "== VPS tun0 iface"
ip -br addr show tun0 2>&1 | head -1
echo "== last 6 server log lines"
journalctl -u openvpn@tun0.service -n 6 --no-pager 2>/dev/null | tail -6
echo DONE
