echo "== ping glorytun VPS end 10.255.254.1"; ping -c3 -W2 10.255.254.1 2>&1 | tail -2
echo "== default route + internet via new VPN"; ip route show default | head -3
echo "curl exit ip:"; timeout 8 curl -s https://ifconfig.me 2>/dev/null || echo "(no internet via vpn yet)"
echo "== camera DNAT rules (still match old openvpn saddr 10.255.252.1?)"
nft list ruleset 2>/dev/null | grep -E '18554|192.168.110.2' | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
