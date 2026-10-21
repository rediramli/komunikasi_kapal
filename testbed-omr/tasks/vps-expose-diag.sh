echo "== socat running?"; pgrep -af 'socat' | grep 8080 || echo "(no socat 8080)"
echo "== 8080 listening (public)?"; ss -tlnp 2>/dev/null | grep ':8080' || echo "(8080 not listening)"
echo "== reverse tunnel: 127.0.0.1:8799 bound?"; ss -tlnp 2>/dev/null | grep '127.0.0.1:8799' || echo "(8799 tunnel NOT up)"
echo "== socat log"; tail -3 /tmp/socat8080.log 2>/dev/null
echo "== firewall rule for 8080?"; nft list ruleset 2>/dev/null | grep '8080' || iptables -L INPUT -n 2>/dev/null | grep 8080 || echo "(no 8080 fw rule)"
echo "== local test: can VPS reach 127.0.0.1:8799 (tunnel->REDLAB live_server)?"
echo "  code: $(timeout 6 curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8799/ 2>&1)"
echo "== local test: VPS -> its own 8080 (socat)?"
echo "  code: $(timeout 6 curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ 2>&1)"
echo DONE
