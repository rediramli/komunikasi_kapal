F=/etc/rc.local
cat > /root/gt-tcp-ip.sh <<'SH'
#!/bin/sh
# workaround: assign glorytun-TCP tun0 IP (OMR init multiqueue bug). Only when glorytun_tcp is the VPN.
[ "$(uci -q get openmptcprouter.settings.vpn)" = glorytun_tcp ] || exit 0
for i in $(seq 1 40); do
  if ip link show tun0 >/dev/null 2>&1; then
    ip addr show tun0 | grep -q 10.255.255.2 || ip addr add 10.255.255.2/32 peer 10.255.255.1 dev tun0
    ip link set tun0 up
    exit 0
  fi
  sleep 2
done
SH
chmod +x /root/gt-tcp-ip.sh
if grep -q 'gt-tcp-ip.sh' "$F"; then echo "(rc.local already has it)"; else
  grep -v '^exit 0$' "$F" > /tmp/rc.new
  echo '(sh /root/gt-tcp-ip.sh &)  # glorytun-TCP tun0 IP workaround' >> /tmp/rc.new
  echo 'exit 0' >> /tmp/rc.new
  cp /tmp/rc.new "$F"; echo "added to rc.local"
fi
echo "== rc.local tail:"; tail -4 "$F"
echo DONE
