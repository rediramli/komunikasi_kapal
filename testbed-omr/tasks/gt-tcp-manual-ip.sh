echo "assign tun0 IP + up"
ip addr add 10.255.255.2/32 peer 10.255.255.1 dev tun0 2>&1 || echo "(addr add failed/exists)"
ip link set tun0 up 2>&1
sleep 2
echo "tun0: $(ip -br addr show tun0 2>&1)"
echo "ping 10.255.255.1: $(ping -c3 -W2 10.255.255.1 2>&1 | tail -1)"
echo DONE
