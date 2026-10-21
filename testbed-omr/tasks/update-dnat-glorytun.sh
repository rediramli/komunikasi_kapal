cd /etc/dlink || exit 1
ts=$(date +%Y%m%d_%H%M%S)
for f in dnat.nft fwd.nft snat.nft; do
  [ -f "$f" ] || continue
  cp -a "$f" "$f.bak.$ts"
  # match both openvpn (10.255.252.1) and glorytun (10.255.254.1) VPS sources
  sed -i 's/ip saddr 10\.255\.252\.1\b/ip saddr { 10.255.252.1, 10.255.254.1 }/g' "$f"
  sed -i 's/ip saddr { 10.255.252.1, 10.255.254.1 }, 10\.255\.254\.1 }//g' "$f"  # noop guard
  echo "-- $f:"; cat "$f"
done
echo "== reload firewall"
fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1
sleep 2
echo "== active DNAT rules now"
nft list ruleset 2>/dev/null | grep -E '18554|192.168.110.2' | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
