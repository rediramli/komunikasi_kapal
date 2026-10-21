echo "== tun0 state"; ip -br addr show tun0 2>&1
echo "== openvpn processes"; pgrep -af openvpn | head
echo "== last 30 openvpn/ovpn-guard log lines"
logread 2>/dev/null | grep -iE 'openvpn|ovpn-guard' | tail -30 | sed 's/admin:[^@]*@/admin:***@/'
echo "== how many ovpn-guard restarts since boot"
logread 2>/dev/null | grep -c 'ovpn-guard.*restart'
echo "== current scheduler"; sysctl -n net.mptcp.scheduler
echo DONE
