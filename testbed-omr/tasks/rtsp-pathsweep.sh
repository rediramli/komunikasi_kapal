H=192.168.110.2
probe() {
  P="$1"
  R=$(printf "DESCRIBE rtsp://$H$P RTSP/1.0\r\nCSeq: 2\r\nUser-Agent: LibVLC/3.0\r\nAccept: application/sdp\r\n\r\n" \
      | timeout 4 nc $H 554 | tr -d '\r' | sed -n '1p')
  printf '%-40s %s\n' "$P" "$R"
}
for P in \
  /live/profile.0 /live/profile.1 /live/profile.2 \
  /live/profile0 /live/profile1 \
  /live.sdp /live1.sdp /live2.sdp \
  /live/ch0 /live/ch1 /live/main /live/sub \
  /video1 /video2 /h264 /stream1 \
  '/cam/realmonitor?channel=1&subtype=0' \
  /11 /12 /0 /1 /profile.0 /onvif1 /media/video1 ; do
  probe "$P"
done
echo "DONE"
