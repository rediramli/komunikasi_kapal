echo "== firewall input chains"
nft list ruleset 2>/dev/null | grep -nE 'chain input|type filter hook input|policy (drop|accept)' | head
echo "== open tcp 8080 on the input chain OMR uses"
if nft list table inet fw4 >/dev/null 2>&1; then
  nft list chain inet fw4 input 2>/dev/null | grep -q 'tcp dport 8080 accept' || nft insert rule inet fw4 input tcp dport 8080 accept
  echo "added to inet fw4 input"
elif nft list table inet filter >/dev/null 2>&1; then
  nft list chain inet filter input 2>/dev/null | grep -q 'tcp dport 8080 accept' || nft insert rule inet filter input tcp dport 8080 accept
  echo "added to inet filter input"
else
  iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
  echo "added via iptables"
fi
echo "== start socat: public 0.0.0.0:8080 -> loopback 8799"
pkill -f 'socat.*8080' 2>/dev/null; sleep 1
setsid socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:8799 </dev/null >/tmp/socat8080.log 2>&1 &
sleep 1
echo "socat: $(pgrep -af 'socat.*8080' | head -1 | cut -c1-70)"
echo "8080 listening: $(ss -tlnp 2>/dev/null | grep ':8080' | head -1)"
echo DONE
