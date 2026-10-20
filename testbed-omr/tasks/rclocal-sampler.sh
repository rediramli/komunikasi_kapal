F=/etc/rc.local
if grep -q 'omr-live.sh' "$F" 2>/dev/null; then
  echo "(already present)"
else
  grep -v '^exit 0$' "$F" > /tmp/rc.new
  echo 'pgrep -f omr-live.sh >/dev/null 2>&1 || (setsid sh /root/omr-live.sh </dev/null >/dev/null 2>&1 &)  # twin sampler persist' >> /tmp/rc.new
  echo 'exit 0' >> /tmp/rc.new
  cp /tmp/rc.new "$F"
  echo "added."
fi
echo "== rc.local now:"; cat "$F"
echo "== sampler still single instance?"
echo "count=$(pgrep -f omr-live.sh | wc -l) pid=$(pgrep -f omr-live.sh | head -1)"
echo DONE
