echo "== MPTCP endpoints (subflow sources)"
ip mptcp endpoint show 2>/dev/null || echo "(ip mptcp not available)"
echo
echo "== MPTCP limits"
ip mptcp limits show 2>/dev/null
echo
echo "== Active MPTCP connections (ss -tniM), look for OpenVPN :1194/tcp"
ss -tniM 2>/dev/null | grep -A3 -iE '1194|mptcp' | head -30 || ss -tni 2>/dev/null | grep -A2 1194 | head -20
echo
echo "== OpenVPN tunnel iface + subflow uplinks"
ip -br addr show tun0 2>/dev/null
echo DONE
