uci get openmptcprouter.settings.vpn
ip -br addr | grep -E 'tun|gt'
pgrep -af glorytun | cut -c1-120
logread | grep -i glorytun | tail -6
