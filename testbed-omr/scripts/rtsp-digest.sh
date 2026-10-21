H=192.168.110.2
U="rtsp://$H/live/profile.0"
printf "RTSP username [admin]: "; read UN; [ -z "$UN" ] && UN=admin
printf "RTSP password: "; stty -echo; read PW; stty echo; echo
md5() { printf '%s' "$1" | openssl md5 | grep -oE '[0-9a-f]{32}' | head -1; }
# step 1: fetch challenge
CH=$(printf "DESCRIBE $U RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n" | timeout 5 nc $H 554 | tr -d '\r')
REALM=$(printf '%s' "$CH" | sed -n 's/.*realm="\([^"]*\)".*/\1/p' | head -1)
NONCE=$(printf '%s' "$CH" | sed -n 's/.*nonce="\([^"]*\)".*/\1/p' | head -1)
echo "challenge realm=$REALM"
echo "challenge nonce=$NONCE"
HA1=$(md5 "$UN:$REALM:$PW")
HA2=$(md5 "DESCRIBE:$U")
RESP=$(md5 "$HA1:$NONCE:$HA2")
# step 2: authenticated DESCRIBE
echo "== authenticated DESCRIBE result:"
printf "DESCRIBE $U RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: Digest username=\"$UN\", realm=\"$REALM\", nonce=\"$NONCE\", uri=\"$U\", response=\"$RESP\"\r\n\r\n" \
  | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,30p'
echo "---- end ----"
echo DONE
