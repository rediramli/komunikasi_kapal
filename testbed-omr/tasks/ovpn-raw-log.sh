echo "== full recent openvpn log (last 20, unfiltered)"
logread 2>/dev/null | grep -i 'openvpn(omr)' | tail -20 | sed 's/admin:[^@]*@/admin:***@/'
echo "== openvpn status file"
cat /var/run/openvpn.omr.status 2>/dev/null | head -8
echo "== can RPi reach VPS:65301 over plain TCP now? (data test)"
(printf 'X'; sleep 2) | timeout 5 nc 168.144.105.155 65301 >/dev/null 2>&1 && echo "tcp connect OK" || echo "tcp connect FAILED"
echo DONE
