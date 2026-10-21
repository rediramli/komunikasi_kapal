echo "== input hook chains (name + policy)"
nft list ruleset 2>/dev/null | awk '/hook input/{print}'
echo "== rules mentioning 8554 / 8888 (how MediaMTX ports are allowed)"
nft list ruleset 2>/dev/null | grep -nE '8554|8888' | head
echo "== rules mentioning 8080"
nft list ruleset 2>/dev/null | grep -nE '8080' | head
echo "== the input chain that OMR uses (full, first 40 lines) - look for reject/drop + where 8080 sits"
for t in fw4 filter; do
  if nft list table inet $t >/dev/null 2>&1; then echo "--- inet $t input ---"; nft list chain inet $t input 2>/dev/null | head -40; fi
done
echo "== any REJECT rules in input"
nft list ruleset 2>/dev/null | grep -iE 'reject' | head
echo DONE
