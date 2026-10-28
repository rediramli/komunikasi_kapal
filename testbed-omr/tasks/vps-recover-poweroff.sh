# Idempotent recovery of the video path after a power-off, VPS side.
#   ./run.sh vps tasks/vps-recover-poweroff.sh
# Fixes the two root causes seen after reboot: (a) leftover Glorytun services on
# the VPS and a stale vpnremoteip make omr-service route the RPi LAN via a dead
# glorytun interface; (b) MediaMTX sources point at an ephemeral tun0 IP.
log(){ echo "  >> $1"; }
echo "== VPS recover $(date -u +%FT%TZ) =="

# 1. retire Glorytun leftovers (the active VPN is OpenVPN)
for s in glorytun-udp@tun0 glorytun-tcp@tun0; do
  systemctl is-active "$s"  >/dev/null 2>&1 && { systemctl stop "$s";    log "stopped $s"; }
  systemctl is-enabled "$s" >/dev/null 2>&1 && { systemctl disable "$s" >/dev/null 2>&1; log "disabled $s"; }
done

# 2. find the live RPi OpenVPN IP on 10.255.252.0/24
RPIIP=""; for i in 2 3 4 5 6; do ping -c1 -W1 10.255.252.$i >/dev/null 2>&1 && { RPIIP=10.255.252.$i; break; }; done
[ -z "$RPIIP" ] && { echo "  !! no RPi on 10.255.252.0/24 - OpenVPN tunnel down? fix the tunnel first, then re-run"; exit 1; }
log "RPi OpenVPN IP = $RPIIP"

# 3. align omr vpnremoteip so omr-service keeps the LAN route via tun0 (not glorytun)
F=/etc/openmptcprouter-vps-admin/omr-admin-config.json
VR=$(jq -r '.users[0].openmptcprouter.vpnremoteip' "$F" 2>/dev/null)
if [ "$VR" != "$RPIIP" ]; then
  cp -a "$F" "$F.bak.$(date +%Y%m%d_%H%M%S)"
  python3 - "$F" "$RPIIP" <<'PY'
import json,sys
f,ip=sys.argv[1],sys.argv[2]; d=json.load(open(f))
d["users"][0]["openmptcprouter"]["vpnremoteip"]=ip
d["users"][0]["openmptcprouter"]["vpnlocalip"]="10.255.252.1"
json.dump(d,open(f,"w"),indent=4)
PY
  log "vpnremoteip $VR -> $RPIIP (backup saved)"
fi

# 4. set the LAN route via tun0 now (omr-service keeps it since vpnremoteip matches)
ip route replace 192.168.100.0/24 via "$RPIIP" dev tun0 && log "route 192.168.100.0/24 via $RPIIP dev tun0"

# 5. MediaMTX sources -> stable LAN IP (never an ephemeral tun0 IP) + reload
MM=/etc/mediamtx/mediamtx.yml
if grep -qE '@10\.255\.25[0-9]\.[0-9]+:' "$MM" 2>/dev/null; then
  cp -a "$MM" "$MM.bak.$(date +%Y%m%d_%H%M%S)"
  sed -i -E 's#@10\.255\.25[0-9]\.[0-9]+:#@192.168.100.1:#g' "$MM"
  log "mediamtx sources -> 192.168.100.1 (backup saved)"
fi
systemctl reload mediamtx 2>/dev/null || systemctl restart mediamtx 2>/dev/null
log "mediamtx reloaded"
echo "== done. verify: ./run.sh vps tasks/vps-health.sh =="
