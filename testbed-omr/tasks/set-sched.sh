sysctl -w net.mptcp.scheduler=default
echo "live scheduler now: $(sysctl -n net.mptcp.scheduler)"
echo "uci persistent:     $(uci -q get network.globals.mptcp_scheduler)  (boot maps to kernel default)"
echo "endpoints:"; ip mptcp endpoint show
