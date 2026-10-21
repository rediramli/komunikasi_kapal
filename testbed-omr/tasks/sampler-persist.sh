chmod +x /root/omr-live.sh
# boot auto-start (idempotent), before 'exit 0'
L='pgrep -f omr-live.sh >/dev/null 2>&1 || (setsid sh /root/omr-live.sh </dev/null >/dev/null 2>&1 &)  # twin sampler (persist)'
if grep -q 'omr-live.sh.*twin sampler' /etc/rc.local 2>/dev/null; then
  echo "(rc.local sampler line already present)"
else
  sed -i "s|^exit 0|$L\nexit 0|" /etc/rc.local && echo "added sampler to rc.local"
fi
echo "== rc.local tail:"; tail -4 /etc/rc.local
echo "== kill old sampler(s), start fresh"
pkill -f omr-live.sh 2>/dev/null; sleep 1
date +%s > /tmp/omr_live.ping
setsid sh /root/omr-live.sh </dev/null >/dev/null 2>&1 &
sleep 4
echo "sampler pid=$(pgrep -f omr-live.sh | head -1)  count=$(pgrep -f omr-live.sh | wc -l)"
echo "csv last: $(tail -1 /tmp/omr_live.csv 2>/dev/null)"
echo DONE
