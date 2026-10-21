echo "== last 25 mediamtx log lines mentioning dlink (PIN masked)"
journalctl -u mediamtx -n 120 --no-pager 2>/dev/null \
  | grep -iE 'dlink|RTSP source|bad status|401|454|auth' \
  | sed 's/admin:[^@]*@/admin:***@/' | tail -25
echo "---- end ----"
