echo "== /root/omr-live.sh exists? (persistent)"
ls -l /root/omr-live.sh 2>&1
echo "== sampler pid alive?"
P=$(cat /tmp/omr_live.pid 2>/dev/null); echo "pid=$P"; kill -0 "$P" 2>/dev/null && echo "ALIVE" || echo "DEAD/none"
echo "== kickstart sampler (write ping + start if dead)"
date +%s > /tmp/omr_live.ping
P=$(cat /tmp/omr_live.pid 2>/dev/null); kill -0 "$P" 2>/dev/null || { nohup sh /root/omr-live.sh </dev/null >/tmp/omr-live.out 2>&1 & sleep 3; echo "started"; }
echo "== omr-live.out (errors?)"
cat /tmp/omr-live.out 2>/dev/null | head
echo "== csv tail (recent samples?)"
tail -4 /tmp/omr_live.csv 2>/dev/null || echo "(no csv)"
echo DONE
