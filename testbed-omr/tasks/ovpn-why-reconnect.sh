echo "== openvpn recent log (reconnect reasons)"
{ logread 2>/dev/null | grep -iE 'openvpn|ovpn'; } | tail -25 | sed 's/admin:[^@]*@/admin:***@/'
echo
echo "== ovpn-guard service + recent action"
if [ -x /etc/init.d/ovpn-guard ]; then
  echo "ovpn-guard enabled=$(/etc/init.d/ovpn-guard enabled 2>/dev/null && echo yes || echo no) running=$(/etc/init.d/ovpn-guard running 2>/dev/null && echo yes || echo '?')"
fi
pgrep -af 'ovpn-guard|ovpn_guard' 2>/dev/null | head
{ logread 2>/dev/null | grep -iE 'ovpn-guard|guard'; } | tail -10
echo
echo "== openvpn uptime (how long current process has run = recent restart?)"
for p in $(pgrep -x openvpn); do echo "pid $p: $(ps -o etime= -p $p 2>/dev/null | tr -d ' ')"; done
echo DONE
