echo "== stuck process state (D=uninterruptible, Z=zombie)"
ps -o pid,stat,wchan:24,cmd -p 3008125 2>/dev/null
echo "== service state"
systemctl is-active openvpn@tun0.service
echo "== try: reset-failed + start (if old proc finally gone)"
systemctl reset-failed openvpn@tun0.service 2>&1
timeout 20 systemctl start openvpn@tun0.service 2>&1 || echo "(start failed/timeout)"
sleep 2
echo "== state now + listener owner"
systemctl is-active openvpn@tun0.service
ss -tlnp 2>/dev/null | grep ':65301'
echo "== still stuck pid?"
ps -o pid,stat,cmd -p 3008125 2>/dev/null || echo "(3008125 gone)"
echo DONE
