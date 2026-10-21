echo "== MPTCP ext counters BEFORE"
nstat -az 2>/dev/null | grep -iE 'MPTcpExtMPJoin|MPTcpExtMPCapable|MPTcpExtMPTCPRetrans|MPTcpExtMPJoinSynAckHMac|MPTcpExtMPJoinNoToken|MPTcpExtMPJoinSynBackup|MPTcpExtAddAddr|MPTcpExtEchoAdd|MPTcpExtMPJoinPortSyn|MPTcpExtMPJoinSynAckBackup|MPTcpExtMPJoinAckRx|MPTcpExtMPRstTx|MPTcpExtMPRstRx|MPTcpExtMPFastcloseTx' > /tmp/m_before 2>/dev/null
cat /tmp/m_before
echo
echo "== starting ip mptcp monitor (40s)"
: > /tmp/mptcp_mon.log
timeout 40 ip mptcp monitor >> /tmp/mptcp_mon.log 2>&1 &
MON=$!
# also sample subflow count every 5s
for k in $(seq 1 8); do
  sleep 5
  n=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '168.144.105.155:[0-9]')
  simba=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '192.168.1.100')
  singtel=$(ss -tnpM 2>/dev/null | grep openvpn | grep -cE '192.168.2.100|wan2')
  echo "t=$((k*5))s  openvpn-tcp-lines=$n simba(wan1)=$simba singtel(wan2)=$singtel"
done
wait $MON 2>/dev/null
echo
echo "== MPTCP monitor events (joins/closes/resets)"
cat /tmp/mptcp_mon.log
echo
echo "== counter DELTAS (after - before)"
nstat -az 2>/dev/null | grep -iE 'MPTcpExtMPJoin|MPTcpExtMPCapable|MPTcpExtMPTCPRetrans|MPTcpExtMPJoinSynAckHMac|MPTcpExtMPJoinNoToken|MPTcpExtAddAddr|MPTcpExtMPRstTx|MPTcpExtMPRstRx|MPTcpExtMPFastclose' > /tmp/m_after 2>/dev/null
join /tmp/m_before /tmp/m_after 2>/dev/null | awk '{d=$3-$2; if(d!=0) printf "%-45s %+d\n",$1,d}'
echo DONE
