# audit-rpi.sh - gambaran konfigurasi OMR (tanpa menampilkan password/key)
echo "### system"; uname -a; grep -E 'DESCRIPTION|RELEASE' /etc/openwrt_release; uptime
echo "### omr settings"; uci show openmptcprouter.settings | grep -viE 'key|pass|token|secret'
echo "### vps"; uci show openmptcprouter.vps | grep -viE 'key|pass|token|secret|username'
echo "### wan"; for w in wan1 wan2; do uci show openmptcprouter.$w | grep -E 'state|multipath|mptcp_status|publicip|asn|latency='; done
echo "### openvpn (uci, tanpa key/cert)"; uci show openvpn | grep -viE 'key|cert|pass|secret|tls_auth|tls_crypt|ca='
echo "### openvpn proses"; ps w | grep '[o]penvpn'
echo "### VPN yang terpasang"; ls /etc/init.d | grep -iE 'glorytun|mlvpn|dsvpn|openvpn|wireguard|mqvpn|omr'
echo "### tun0 & route"; ip -br addr | grep -E 'tun|wg|gt-'; ip route | head -6
echo "### mptcp"; ip mptcp limits show; ip mptcp endpoint show
echo "### subflow OpenVPN (:65301)"; ss -tan | grep ':65301' 
echo "### shadowsocks"; uci show shadowsocks-rust | grep -E '\.server=|\.disabled=|=ss_redir|=server|=ss_local'
echo "### omr-tracker"; uci show omr-tracker | grep -E 'interval|timeout|tries|failure'; logread | grep -iE 'omr-tracker-ss|Can.t find' | tail -3
echo "### paket glorytun"; apk info 2>/dev/null | grep -iE 'glorytun|mlvpn|dsvpn|openvpn'
