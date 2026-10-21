echo "== proses"; pgrep -af openvpn || echo "openvpn TIDAK jalan"
echo "== ping VPS per link"; for w in wan1 wan2; do ping -c2 -W2 -I $w 168.144.105.155 | tail -1; done
echo "== restart openvpn"; /etc/init.d/openvpn restart; sleep 20
ip -4 addr show tun0 | grep inet || echo "tun0 masih TIDAK ADA"
ss -tn | grep ':65301'
logread | grep -iE "openvpn" | tail -6
