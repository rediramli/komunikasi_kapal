echo "== openvpn server process + port 65301 listening?"
pgrep -af openvpn | head
ss -tlnp 2>/dev/null | grep -E ':65301' || echo "(nothing listening on 65301!)"
echo
echo "== VPS tun interface (server end 10.255.252.1?)"
ip -br addr | grep -E 'tun|10.255.252'
echo
echo "== recent VPS openvpn log"
journalctl -u openvpn* -n 20 --no-pager 2>/dev/null | tail -20 || { logread 2>/dev/null | grep -i openvpn | tail -20; } || tail -20 /var/log/openvpn*.log 2>/dev/null
echo
echo "== omr services on VPS (shadowsocks/openvpn)"
systemctl list-units --type=service --state=running 2>/dev/null | grep -iE 'openvpn|shadow|omr|glorytun' | head
echo DONE
