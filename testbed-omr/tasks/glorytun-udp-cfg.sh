echo "== all glorytun uci sections (udp + tcp)"
uci show glorytun 2>/dev/null | sed 's/key=.*/key=***/'
echo
echo "== glorytun-udp uci (separate package?)"
uci show glorytun-udp 2>/dev/null | sed 's/key=.*/key=***/' | head
echo
echo "== omr vpn setting + any list of valid vpns"
uci show openmptcprouter 2>/dev/null | grep -iE 'vpn|proxy' | head
echo
echo "== omr helper scripts for switching vpn"
ls /usr/bin/omr-* /usr/libexec/omr* 2>/dev/null | grep -iE 'vpn|service' | head
echo "grep vpn switch in omr init:"
grep -rl 'settings.vpn\|glorytun' /etc/init.d/ 2>/dev/null | head
echo DONE
