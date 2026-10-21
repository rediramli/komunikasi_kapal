ip addr add 10.255.254.2/32 peer 10.255.254.1 dev tun0 2>/dev/null || echo "(exists)"
ip link set tun0 up
sleep 2
echo "tun0: $(ip -br addr show tun0)"
echo "ping VPS 10.255.254.1: $(ping -c2 -W2 10.255.254.1 2>&1 | tail -1)"
echo DONE
