echo "== VPN OMR"; uci -q get openmptcprouter.settings.vpn
echo "== interface tunnel"; ip -4 -br addr | grep -E '10\.255\.' || echo "tidak ada tunnel 10.255.x"
echo "== proses VPN"; pgrep -af 'glorytun|mlvpn|openvpn|wireguard|dsvpn' || echo "tidak ada"
echo "== instance openvpn"; uci show openvpn | grep -E "^openvpn\.[a-z_]+=|enabled" | head
echo "== koneksi ke VPS"; ss -tnu | grep 168.144.105.155 | head
echo "== log VPN"; logread | grep -iE 'glorytun|mlvpn|openvpn|vpn' | tail -8
