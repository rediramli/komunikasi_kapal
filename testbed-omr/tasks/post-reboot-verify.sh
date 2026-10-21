echo "== uptime (should be small = fresh boot)"
uptime
echo
echo "== scheduler (persisted?)"
echo "uci=$(uci -q get network.globals.mptcp_scheduler)  live=$(sysctl -n net.mptcp.scheduler)"
echo
echo "== MPTCP endpoints"
ip mptcp endpoint show
echo
echo "== OpenVPN tunnel + subflows (want BOTH wan1 + wan2)"
ip -br addr show tun0
ss -tnpM 2>/dev/null | grep openvpn | grep -E '168.144.105.155' | awk '{print "  "$4" -> "$5}'
echo "wan2 subflow present: $(ss -tnpM 2>/dev/null | grep openvpn | grep -cE 'wan2|192.168.2.100')"
echo
echo "== ovpn-guard restarts since boot"
logread 2>/dev/null | grep -c 'ovpn-guard.*restart'
echo DONE
