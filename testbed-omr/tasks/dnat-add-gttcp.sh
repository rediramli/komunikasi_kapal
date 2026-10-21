cd /etc/dlink || exit 1
for f in dnat.nft fwd.nft snat.nft; do
  [ -f "$f" ] || continue
  # add 10.255.255.1 to the saddr set if not present
  grep -q '10.255.255.1' "$f" || sed -i 's/10\.255\.254\.1 }/10.255.254.1, 10.255.255.1 }/' "$f"
done
fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1
echo "DNAT now:"; nft list ruleset 2>/dev/null | grep '18554' | sed 's/admin:[^@]*@/admin:***@/'
echo DONE
