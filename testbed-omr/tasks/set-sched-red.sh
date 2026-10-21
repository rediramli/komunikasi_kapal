echo "== BEFORE: uci=$(uci -q get network.globals.mptcp_scheduler)  live=$(sysctl -n net.mptcp.scheduler)"
# persist (OMR init /etc/init.d/mptcp applies network.globals.mptcp_scheduler at boot)
uci set network.globals.mptcp_scheduler='bpf_red'
uci commit network
# live
sysctl -w net.mptcp.scheduler=bpf_red >/dev/null
echo "== AFTER:  uci=$(uci -q get network.globals.mptcp_scheduler)  live=$(sysctl -n net.mptcp.scheduler)"
echo "endpoints:"; ip mptcp endpoint show
echo DONE
