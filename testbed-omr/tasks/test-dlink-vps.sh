echo "== Rute tun0 di VPS"
ip route show dev tun0
RPI=$(ip neigh show dev tun0 2>/dev/null | awk '{print $1}' | head -1)
[ -z "$RPI" ] && RPI=$(grep -hoE '^10\.255\.252\.[0-9]+' /etc/openvpn/*status* /var/log/openvpn*status* /run/openvpn*/*status* 2>/dev/null | head -1)
[ -z "$RPI" ] && RPI=10.255.252.2
echo "== RTSP OPTIONS ke $RPI:8554"
bash -c "exec 3<>/dev/tcp/$RPI/8554 && printf 'OPTIONS rtsp://$RPI:8554/live/profile.0 RTSP/1.0\r\nCSeq: 1\r\n\r\n' >&3 && timeout 3 head -4 <&3" || echo "GAGAL konek ke $RPI"
echo "== Lokasi config MediaMTX"
systemctl cat mediamtx 2>/dev/null | grep -E 'ExecStart|WorkingDirectory'
ls -l /etc/mediamtx* /usr/local/etc/mediamtx* /opt/mediamtx* 2>/dev/null
