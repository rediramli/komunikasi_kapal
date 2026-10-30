#!/bin/sh
# tun0 watchdog — keeps the camera path alive on the RPi.
# If the OpenVPN tunnel interface tun0 has no IPv4 (the recurring failure that
# makes MediaMTX lose the cameras), clear any stale tun0 and restart OpenVPN so
# the tunnel reconnects. Safe to run often; a no-op when tun0 is healthy.
# Install (on the RPi), run every 3 min from cron:
#   cat > /root/tun0-watchdog.sh < this file ; chmod +x /root/tun0-watchdog.sh
#   echo "*/3 * * * * /root/tun0-watchdog.sh" >> /etc/crontabs/root
#   /etc/init.d/cron enable ; /etc/init.d/cron restart
#
# Note: this restarts the OpenVPN CLIENT only (RPi side); it normally reclaims
# 10.255.252.2, which the VPS route already targets. If the RPi ever reconnects
# on a different tunnel IP, re-run tasks/vps-recover-poweroff.sh on the VPS.
if ip -4 addr show tun0 2>/dev/null | grep -q "inet "; then
  exit 0
fi
logger -t tun0wd "tun0 has no IPv4 — restarting OpenVPN"
/etc/init.d/openvpn stop 2>/dev/null
sleep 2
ip link del tun0 2>/dev/null
/etc/init.d/openvpn start 2>/dev/null
# wait briefly and log the outcome
i=0
while [ $i -lt 12 ]; do
  sleep 2; i=$((i+1))
  A=$(ip -4 addr show tun0 2>/dev/null | grep -oE "inet [0-9.]+" | head -1)
  [ -n "$A" ] && { logger -t tun0wd "tun0 back: $A"; exit 0; }
done
logger -t tun0wd "tun0 still down after restart"
