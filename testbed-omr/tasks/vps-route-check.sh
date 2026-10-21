ip route | grep -E '192.168.100.0' | head -1
echo "ping RPi 10.255.254.2: $(ping -c2 -W2 10.255.254.2 2>&1 | tail -1)"
