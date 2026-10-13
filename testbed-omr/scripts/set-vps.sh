#!/bin/sh
# Point the OMR router at a (new) OMR VPS.
# Usage: sh set-vps.sh <VPS_IP> [ssh_port]
# Pulls the API password of user "openmptcprouter" straight from the VPS
# (omr-admin-config.json), verifies login, then stores it. You will be asked
# for the VPS root password once.
set -e
VPS="$1"; SSHP="${2:-65222}"
[ -n "$VPS" ] || { echo "usage: $0 <VPS_IP> [ssh_port]"; exit 1; }
J=/etc/openmptcprouter-vps-admin/omr-admin-config.json

KEY=$(ssh -p "$SSHP" root@"$VPS" python3 - <<PYEOF
import json
def find(o):
    if isinstance(o, dict):
        if o.get('username') == 'openmptcprouter' and 'user_password' in o:
            return o['user_password']
        o = list(o.values())
    if isinstance(o, list):
        for v in o:
            r = find(v)
            if r: return r
print(find(json.load(open('$J'))) or '', end='')
PYEOF
)
[ ${#KEY} -ge 32 ] || { echo "could not read key (len ${#KEY})"; exit 1; }

curl -sk -m 30 -X POST "https://$VPS:65500/token" \
	-d "username=openmptcprouter&password=$KEY" | grep -q access_token \
	|| { echo "API login failed - check VPS"; exit 1; }
echo "API login OK"

# NOTE: 'ip' is a LIST. 'uci set ...ip=' turns it into an option and the
# init script silently finds no server ("Can't get vps token, try later ()").
uci -q delete openmptcprouter.vps.ip || true
uci add_list openmptcprouter.vps.ip="$VPS"
uci set openmptcprouter.vps.username='openmptcprouter'
uci set openmptcprouter.vps.password="$KEY"
uci set openmptcprouter.vps.port='65500'
uci -q delete openmptcprouter.vps.token || true
uci set openmptcprouter.vps.get_config='1'
uci set openmptcprouter.vps.token_error='0'
uci set openmptcprouter.vps.admin_error='0'
uci commit openmptcprouter
/etc/init.d/openmptcprouter-vps restart
sleep 45
uci show openmptcprouter.vps | grep -E "error|kernel|omr_version|get_config"
echo "Expect admin_error='0' and get_config='0'. Then reboot the router."
