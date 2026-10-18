printf "PIN: "; stty -echo; read P; stty echo; echo
A=$(printf 'admin:%s' "$P" | openssl base64)
H=192.168.110.2
t() {
  echo "== $1"
  printf "$2" | nc -w3 $H 554 | grep -E 'RTSP/|WWW-Auth|m=video|a=rtpmap' | head -4
}
U1="rtsp://$H/live/profile.0"
U2="rtsp://$H:554/live/profile.0"
t "A: tanpa login, url tanpa port" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
t "B: tanpa login, url :554" \
  "DESCRIBE $U2 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
t "C: Basic preemptive, url tanpa port" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: Basic $A\r\n\r\n"
t "D: OPTIONS lalu DESCRIBE satu koneksi" \
  "OPTIONS $U1 RTSP/1.0\r\nCSeq: 1\r\n\r\nDESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
