printf "PIN: "; stty -echo; read P; stty echo; echo
A=$(printf 'admin:%s' "$P" | openssl base64)
H=192.168.110.2
raw() {
  echo
  echo "######## $1"
  printf "$2" | timeout 6 nc $H 554 | tr -d '\r' | sed -n '1,25p'
  echo "---- end ----"
}
U1="rtsp://$H/live/profile.0"
raw "A: OPTIONS no-login" \
  "OPTIONS $U1 RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: LibVLC/3.0\r\n\r\n"
raw "B: DESCRIBE no-login, url no port" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n"
raw "C: DESCRIBE Basic preemptive" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\nAuthorization: Basic $A\r\n\r\n"
raw "D: OPTIONS then DESCRIBE one connection" \
  "OPTIONS $U1 RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: LibVLC/3.0\r\n\r\nDESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n"
echo
echo "ALL DONE"
