echo "== OMR proxy/VPN in use (uci)"
echo "default_proxy: $(uci -q get openmptcprouter.settings.proxy)"
echo "vpn:           $(uci -q get openmptcprouter.settings.vpn)"
echo
echo "== running tunnel/proxy services"
for s in shadowsocks-libev shadowsocks-rust glorytun glorytun-udp openvpn v2ray xray dsvpn mlvpn ; do
  if [ -x /etc/init.d/$s ]; then
    printf "%-18s enabled=%s running=%s\n" "$s" "$(/etc/init.d/$s enabled 2>/dev/null && echo yes || echo no)" "$(/etc/init.d/$s running 2>/dev/null && echo yes || echo '?')"
  fi
done
echo
echo "== who owns the MPTCP conns to the VPS (65280/65301)"
ss -tnpM 2>/dev/null | grep -E '168.144.105.155' | sed -E 's/.*users:\(\((.*)\)\).*/\1/' | sort -u | head
echo
echo "== openvpn remote/proto (how the camera tunnel reaches the VPS)"
grep -hiE '^remote |^proto |^port ' /etc/openvpn/*.conf /etc/openvpn/*.ovpn 2>/dev/null | sed 's/admin:[^@]*@/admin:***@/' | head
echo DONE
