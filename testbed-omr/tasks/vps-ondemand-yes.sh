set -e
F=/etc/mediamtx/mediamtx.yml
B=/etc/mediamtx/mediamtx.yml.bak.$(date +%Y%m%d_%H%M%S)
cp -a "$F" "$B"
echo "backup: $B"
n=$(grep -c '^    sourceOnDemand: no$' "$F" || true)
echo "matches of 'sourceOnDemand: no': $n"
if [ "$n" = "1" ]; then
  sed -i 's/^    sourceOnDemand: no$/    sourceOnDemand: yes/' "$F"
  echo "changed."
else
  echo "ABORT: expected exactly 1 match, got $n"; exit 1
fi
echo "== dlink block now (PIN masked)"
awk 'NR>=889 && NR<=898' "$F" | sed 's/admin:[^@]*@/admin:***@/'
echo "== restart mediamtx"
systemctl restart mediamtx
sleep 2
systemctl is-active mediamtx
echo "== last 6 journal lines (PIN masked)"
journalctl -u mediamtx -n 6 --no-pager 2>/dev/null | sed 's/admin:[^@]*@/admin:***@/'
