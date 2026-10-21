echo "== locate mediamtx rule: table / chain / handle"
nft -a list ruleset 2>/dev/null | awk '
  /table .* \{/{tbl=$0}
  /chain .* \{/{chn=$0}
  /mediamtx-tcp/{print "TABLE:"tbl; print "CHAIN:"chn; print "RULE :"$0}
'
echo "== that chain, full, to see where accepts vs reject sit"
nft -a list ruleset 2>/dev/null | awk '
  /chain .* \{/{c=$2}
  c && /mediamtx-tcp/{found=c}
'
# print the chain containing mediamtx
CH=$(nft -a list ruleset 2>/dev/null | awk '/chain /{c=$2} /mediamtx-tcp/{print c; exit}')
echo "chain name = $CH"
nft -a list chain inet fw4 "$CH" 2>/dev/null | head -30 || true
echo DONE
