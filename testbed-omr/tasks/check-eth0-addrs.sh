echo "== eth0 addresses now (post-reboot)"
ip -br addr show eth0
echo
echo "== route to camera"
ip route get 192.168.110.2 2>&1
echo
echo "== uci network interfaces with 192.168.110 or 192.168.1.250 (persistent?)"
uci show network 2>/dev/null | grep -E '192\.168\.(110|1\.250)' || echo "(no uci entry for these -> they were manual/non-persistent)"
echo
echo "== any uci alias interfaces on eth0"
uci show network 2>/dev/null | grep -iE "ipaddr|device='eth0'|ifname" | grep -iE '110|1\.250|100\.1' | head
echo DONE
