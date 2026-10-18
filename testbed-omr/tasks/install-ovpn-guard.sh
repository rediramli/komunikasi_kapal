# install-ovpn-guard.sh - pasang penjaga: tunnel OpenVPN (MPTCP) harus punya subflow di setiap link yang up.
# Kernel tidak membuat ulang subflow dari alamat subflow AWAL setelah link itu putus-sambung,
# jadi penjaga me-restart OpenVPN (jeda ±2 s) bila sebuah link up >20 s tanpa subflow tunnel.
# Copot:  /etc/init.d/ovpn-guard disable; /etc/init.d/ovpn-guard stop
cat > /root/ovpn-guard.sh <<'EOF'
#!/bin/sh
IP1=$(uci -q get network.wan1.ipaddr); IP2=$(uci -q get network.wan2.ipaddr)
m1=0; m2=0; last=0
while :; do
  sleep 5
  [ "$(uci -q get openmptcprouter.settings.vpn)" = openvpn ] || continue
  ov=$(ss -tan 2>/dev/null | grep ESTAB | grep ':65301')
  [ -n "$ov" ] || continue                     # tunnel sedang reconnect sendiri
  if [ "$(uci -q get openmptcprouter.wan1.state)" = up ] && ! echo "$ov" | grep -q "$IP1[%:]"; then m1=$((m1+5)); else m1=0; fi
  if [ "$(uci -q get openmptcprouter.wan2.state)" = up ] && ! echo "$ov" | grep -q "$IP2[%:]"; then m2=$((m2+5)); else m2=0; fi
  now=$(date +%s)
  if { [ $m1 -ge 20 ] || [ $m2 -ge 20 ]; } && [ $((now-last)) -ge 120 ]; then
    logger -t ovpn-guard "link up tanpa subflow tunnel (wan1 ${m1}s, wan2 ${m2}s) -> restart openvpn"
    /etc/init.d/openvpn restart; last=$now; m1=0; m2=0
  fi
done
EOF
chmod +x /root/ovpn-guard.sh
cat > /etc/init.d/ovpn-guard <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
  procd_open_instance
  procd_set_param command /bin/sh /root/ovpn-guard.sh
  procd_set_param respawn
  procd_close_instance
}
EOF
chmod +x /etc/init.d/ovpn-guard
/etc/init.d/ovpn-guard enable; /etc/init.d/ovpn-guard restart
sleep 2; pgrep -f ovpn-guard.sh >/dev/null && echo "ovpn-guard: jalan" || echo "ovpn-guard: GAGAL start"
echo "### subflow tunnel sekarang:"; ss -tan | grep ESTAB | grep ':65301'
echo "(bila hanya 1 baris, penjaga akan me-restart OpenVPN dalam ±20-25 s)"
