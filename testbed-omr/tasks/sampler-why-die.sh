echo "== sampler process alive?"
pgrep -af omr-live.sh | head || echo "(not running)"
echo "== pid file + ping age"
echo "pid=$(cat /tmp/omr_live.pid 2>/dev/null)  ping=$(cat /tmp/omr_live.ping 2>/dev/null)  now=$(date +%s)"
echo "ping age = $(( $(date +%s) - $(cat /tmp/omr_live.ping 2>/dev/null || echo 0) )) s (stops at >900)"
echo "== csv last line + age"
tail -1 /tmp/omr_live.csv 2>/dev/null; echo "csv mtime age = $(( $(date +%s) - $(stat -c %Y /tmp/omr_live.csv 2>/dev/null || echo 0) )) s"
echo "== start it + confirm it stays (watch 5s)"
pgrep -f omr-live.sh >/dev/null 2>&1 || { date +%s > /tmp/omr_live.ping; nohup sh /root/omr-live.sh </dev/null >/tmp/omr-live.err 2>&1 & sleep 1; }
sleep 5
echo "after 5s: pid=$(pgrep -f omr-live.sh | head -1) csv_last=$(tail -1 /tmp/omr_live.csv 2>/dev/null)"
echo "== any error from sampler"
cat /tmp/omr-live.err 2>/dev/null | head
echo DONE
