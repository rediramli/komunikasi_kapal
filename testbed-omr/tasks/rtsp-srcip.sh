echo "== ip addr (eth0 and any 192.168.110/100)"
ip -o addr show | grep -E '192\.168\.(110|100)\.' || ip -o addr show
echo
echo "== route to camera"
ip route get 192.168.110.2
echo
echo "== all eth links brief"
ip -br addr
