# openvpn-restart.sh - buat ulang koneksi tunnel OpenVPN (MPTCP) supaya punya subflow di semua link yang up
echo "### sebelum"; ss -tan | grep ':65301'; ip -br addr show tun0
/etc/init.d/openvpn restart
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 2; n=$(ss -tan | grep ESTAB | grep -c ':65301'); [ "$n" -ge 2 ] && break; done
echo "### sesudah ($((i*2)) s)"; ss -tan | grep ':65301'; ip -br addr show tun0
ping -c3 -W2 10.255.252.1 | tail -1
