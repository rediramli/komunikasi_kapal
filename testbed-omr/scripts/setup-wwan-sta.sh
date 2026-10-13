#!/bin/sh
# Temporary uplink: RPi on-board Wi-Fi as a client of a hotspot / lab AP.
# Usage: sh setup-wwan-sta.sh "<SSID>" [psk]   (no psk = open network)
# Band must match the AP: check with  iw dev <iface> scan | grep -E "freq:|SSID:|Authentication"
# WPA2-Enterprise (eduroam, SIT-WIFI) is not supported by the default wpad.
set -e
SSID="$1"; PSK="$2"; BAND="${BAND:-2g}"
[ -n "$SSID" ] || { echo "usage: $0 <SSID> [psk]"; exit 1; }
uci -q delete wireless.default_radio0 || true      # default open AP "OpenWrt"
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='SG'
uci set wireless.radio0.band="$BAND"
uci set wireless.radio0.channel='auto'
[ "$BAND" = "2g" ] && uci set wireless.radio0.htmode='HT20' || uci set wireless.radio0.htmode='VHT80'
uci set wireless.wwan=wifi-iface
uci set wireless.wwan.device='radio0'
uci set wireless.wwan.mode='sta'
uci set wireless.wwan.network='wwan'
uci set wireless.wwan.ssid="$SSID"
if [ -n "$PSK" ]; then
	uci set wireless.wwan.encryption='psk2'
	uci set wireless.wwan.key="$PSK"
else
	uci set wireless.wwan.encryption='none'
fi
uci set network.wwan=interface
uci set network.wwan.proto='dhcp'
uci set network.wwan.multipath='on'
ZONE=$(uci show firewall | grep "\.name='wan'" | cut -d. -f2)
uci show firewall | grep -q "network=.*wwan" || uci add_list firewall.$ZONE.network='wwan'
uci commit
wifi reload
service network reload
service firewall restart
sleep 15
iw dev | grep -A1 Interface
ifstatus wwan | grep -A3 '"ipv4-address"'
