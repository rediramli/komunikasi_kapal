# Idempotent recovery after a power-off, RPi side.
#   ./run.sh rpi tasks/recover-after-poweroff.sh
# Then the VPS side:  ./run.sh vps tasks/vps-recover-poweroff.sh
log(){ echo "  >> $1"; }
echo "== RPi recover $(date -u +%FT%TZ) =="

# 1. clock: RPi4 has no RTC. Step it once the tunnel/internet is up, restart Tailscale.
if [ -x /root/omr-timesync.sh ]; then /root/omr-timesync.sh; log "clock synced -> $(date -u +%FT%TZ)"; else log "WARN /root/omr-timesync.sh missing (install it for boot-time clock)"; fi

# 2. VPN consistency (do NOT force-switch here; that must go through OMR/dashboard)
V=$(uci -q get openmptcprouter.settings.vpn)
[ "$V" = openvpn ] && log "settings.vpn=openvpn" || log "WARN settings.vpn=$V (expected openvpn; switch via dashboard/OMR)"
pgrep -f glorytun-udp >/dev/null && log "WARN glorytun-udp running on RPi (should be off under OpenVPN)" || log "glorytun-udp not running"

# 3. tun0 overlay up
if ip -4 addr show tun0 2>/dev/null | grep -q 'inet 10.255.252'; then
  log "tun0 ok ($(ip -4 addr show tun0 | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1))"
else
  log "WARN tun0 has no 10.255.252.x IP - OpenVPN down; check /etc/init.d/openvpn"
fi

# 4. camera DNAT/forward rules loaded (reload fw4 includes if missing)
if nft list chain inet fw4 dstnat 2>/dev/null | grep -q 'dport 1855'; then
  log "camera DNAT rules present"
else
  fw4 reload >/dev/null 2>&1; log "fw4 reloaded (camera DNAT was missing)"
fi

# 5. persist bits from rc.local (camera-LAN alias + twin sampler)
ip -4 addr show eth0 2>/dev/null | grep -q '192.168.110.250' || { ip addr add 192.168.110.250/24 dev eth0 2>/dev/null; log "re-added camera-LAN alias 192.168.110.250"; }
pgrep -f omr-live.sh >/dev/null || { setsid sh /root/omr-live.sh </dev/null >/dev/null 2>&1 & log "restarted twin sampler"; }

echo "== done. Now run the VPS side:  ./run.sh vps tasks/vps-recover-poweroff.sh =="
echo "== then verify:  ./run.sh rpi tasks/check-health.sh  &&  ./run.sh vps tasks/vps-health.sh =="
