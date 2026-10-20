echo "== mediamtx listeners (8554/8888?)"
ss -tlnp 2>/dev/null | grep -E ':8554|:8888|:1935' | head
echo "== mediamtx recent log"
journalctl -u mediamtx -n 8 --no-pager 2>/dev/null | tail -8 | sed 's/admin:[^@]*@/admin:***@/'
echo "== can VPS reach camera via tunnel now?"
printf "OPTIONS rtsp://192.168.100.1:18554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n" | timeout 5 nc 192.168.100.1 18554 2>/dev/null | head -1 || echo "(no camera path yet)"
echo DONE
