echo "tun0: $(ip -br addr show tun0 2>/dev/null)"
echo "ping VPS tunnel 10.255.255.1: $(ping -c2 -W2 10.255.255.1 2>&1 | tail -1)"
echo "== glorytun processes"
pgrep -af glorytun | head
echo "== glorytun TCP connection to VPS:65001 + MPTCP?"
ss -tnp 2>/dev/null | grep ':65001' | head
echo "-- MPTCP level:"
ss -tnpiM 2>/dev/null | grep -A1 ':65001' | grep -oE 'subflows_total:[0-9]+|tcp-ulp-mptcp' | head
echo "== internet via VPN"; timeout 8 curl -s https://ifconfig.me 2>/dev/null || echo "(no internet)"
echo "== default route"; ip route show default | head -2
echo DONE
