#!/bin/sh
# Install the static Tailscale arm64 build on OMR (no tailscale package in the OMR repo).
# 1. On a laptop, download tailscale_<ver>_arm64.tgz from https://pkgs.tailscale.com/stable/#static
#    (make sure it is arm64, not amd64)
# 2. scp -O tailscale_<ver>_arm64.tgz root@192.168.100.1:/tmp/
# 3. Copy this script and tailscale.init to /tmp on the router and run: sh /tmp/install-tailscale.sh
set -e
cd /tmp
F=$(ls tailscale_*_arm64.tgz 2>/dev/null | head -1)
[ -n "$F" ] || { echo "no /tmp/tailscale_*_arm64.tgz found"; exit 1; }
tar xzf "$F"
D=${F%.tgz}
cp "$D/tailscale" "$D/tailscaled" /usr/sbin/
mkdir -p /etc/tailscale
[ -f /tmp/tailscale.init ] && cp /tmp/tailscale.init /etc/init.d/tailscale
chmod +x /etc/init.d/tailscale
/etc/init.d/tailscale enable
/etc/init.d/tailscale restart
sleep 3
tailscale version
rm -rf "$D" "$F"
echo
echo "Now run: tailscale up --netfilter-mode=off --accept-dns=false --hostname=omr-rpi4"
echo "then:    sh setup-tailscale-fw.sh"
echo "Disable key expiry for this machine in the Tailscale admin console."
