H=192.168.110.2
U="rtsp://$H/live/profile.0"
shot() {
  echo
  echo "######## $1"
  printf "$2" | timeout 5 nc $H 554 | tr -d '\r' | sed -n '1,20p'
  echo "---- end ----"
}
shot "1: DESCRIBE with garbage Digest (provoke challenge)" \
  "DESCRIBE $U RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\nAuthorization: Digest username=\"admin\", realm=\"\", nonce=\"\", uri=\"$U\", response=\"00000000000000000000000000000000\"\r\n\r\n"
shot "2: SETUP track no-auth" \
  "SETUP $U/trackID=0 RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n\r\n"
shot "3: GET_PARAMETER no-auth" \
  "GET_PARAMETER $U RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\n\r\n"
shot "4: DESCRIBE garbage Basic" \
  "DESCRIBE $U RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\nAuthorization: Basic Zm9vOmJhcg==\r\n\r\n"
shot "5: PLAY no-auth (expect error, check which)" \
  "PLAY $U RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nSession: 12345678\r\n\r\n"
echo
echo "DONE"
