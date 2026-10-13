#!/bin/sh
# Allow SSH/LuCI from Tailscale WITHOUT creating a netifd interface for tailscale0.
# A netifd 'proto none' interface strips the 100.x address, and OMR then treats it
# like a WAN (adds ip4table/metric). Bind the firewall zone to the device instead.
set -e
uci -q delete network.tailscale || true
if ! uci show firewall | grep -q "name='tailscale'"; then
	uci add firewall zone >/dev/null
	uci set firewall.@zone[-1].name='tailscale'
	uci set firewall.@zone[-1].input='ACCEPT'
	uci set firewall.@zone[-1].output='ACCEPT'
	uci set firewall.@zone[-1].forward='REJECT'
	uci add_list firewall.@zone[-1].device='tailscale0'
fi
# dropbear must not be bound to lan only
uci -q delete dropbear.@dropbear[0].Interface || true
uci commit
service network reload
service firewall restart
service dropbear restart
/etc/init.d/tailscale restart
sleep 5
ip -br addr show tailscale0
ip mptcp endpoint show   # tailscale0 must NOT appear here
