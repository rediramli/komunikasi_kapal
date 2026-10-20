# kill any stale, start fresh explicitly
date +%s > /tmp/omr_live.ping
P=$(cat /tmp/omr_live.pid 2>/dev/null)
[ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo "already running pid=$P" || {
  setsid sh /root/omr-live.sh </dev/null >/tmp/omr-live.out 2>&1 &
  sleep 3
  echo "started; new pid=$(cat /tmp/omr_live.pid 2>/dev/null)"
}
echo "== out:"; cat /tmp/omr-live.out 2>/dev/null | head
echo "== csv tail:"; tail -3 /tmp/omr_live.csv 2>/dev/null || echo "(still no csv)"
echo DONE
