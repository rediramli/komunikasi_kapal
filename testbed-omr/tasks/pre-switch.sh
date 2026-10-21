echo "== MAC kamera (catat!)"; ping -c1 -W1 192.168.110.2 >/dev/null; ip neigh | grep '192.168.110.2 '
echo "== wan statis?"; for w in wan1 wan2; do echo "$w: $(uci -q get network.$w.proto) $(uci -q get network.$w.ipaddr)"; done
