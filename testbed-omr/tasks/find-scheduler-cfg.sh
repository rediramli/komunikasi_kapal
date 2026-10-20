echo "== live sysctl"
sysctl net.mptcp.scheduler 2>/dev/null
echo
echo "== OMR uci keys mentioning scheduler"
uci show 2>/dev/null | grep -iE 'schedul' || echo "(none in uci)"
echo
echo "== sysctl config files setting mptcp scheduler"
grep -RniE 'mptcp.*schedul|scheduler' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null || echo "(none in sysctl.d)"
echo
echo "== any omr/service file that sets the scheduler"
grep -RniE 'net.mptcp.scheduler|mptcp_scheduler|bpf_bkup|bpf_burst|bpf_red' /etc/ 2>/dev/null | grep -vE '\.bak' | head -20
echo DONE
