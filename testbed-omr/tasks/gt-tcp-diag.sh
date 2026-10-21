echo "== glorytun service"
/etc/init.d/glorytun enabled 2>/dev/null && echo "enabled" || echo "not-enabled"
/etc/init.d/glorytun running 2>/dev/null && echo "running" || echo "not-running"
echo "== try start glorytun"
/etc/init.d/glorytun start 2>&1 | head
sleep 3
pgrep -af glorytun | head
echo "== glorytun log"
logread 2>/dev/null | grep -iE 'glorytun' | tail -8
echo DONE
