echo "== openvpn@tun0 service state"; systemctl is-active openvpn@tun0.service 2>/dev/null
echo "== tun0 process state (Ds=wedged)"; ps -eo pid,stat,wchan:16,cmd | grep -E 'ovpn-tun0' | grep -v grep | head
echo "== listening 65301?"; ss -tlnp 2>/dev/null | grep ':65301' | head -1 || echo "(not listening)"
echo "== VPS tun0 iface"; ip -br addr show tun0 2>&1 | head -1
echo "== routing table (RPi client sessions)"; grep -iE '10.255.252' /run/openvpn/tun0.status 2>/dev/null | head
echo "== last 8 server log"; journalctl -u openvpn@tun0.service -n 8 --no-pager 2>/dev/null | tail -8
echo DONE
