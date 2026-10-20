sysctl -w net.mptcp.scheduler=default
echo "$(date +%s) default" >> /tmp/omr_sched.log
/etc/init.d/openvpn restart; sleep 20
ss -tn | grep ':65301'
