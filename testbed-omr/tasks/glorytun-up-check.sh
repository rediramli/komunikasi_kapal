echo "== settings.vpn now"; uci -q get openmptcprouter.settings.vpn
echo "== glorytun-udp enable + openvpn enable"
echo "glorytun-udp.enable=$(uci -q get glorytun-udp.vpn.enable)  glorytun.enable=$(uci -q get glorytun.vpn.enable)  openvpn.omr.enabled=$(uci -q get openvpn.omr.enabled)"
echo "== wait up to 45s for a glorytun tunnel iface (gt-udp/tun with 10.255.254/255)"
for i in $(seq 1 15); do
  sleep 3
  t=$(ip -br addr | grep -iE 'gt-|tun' | grep -E '10.255.25[0-9]')
  [ -n "$t" ] && { echo "tunnel up at ${i}x3s:"; echo "$t"; break; }
done
echo "== all tunnel ifaces now"; ip -br addr | grep -iE 'tun|gt-|10.255' 
echo "== omr vpn status"; uci -q get openmptcprouter.omr.vpn
echo "== glorytun-udp service"; /etc/init.d/glorytun-udp status 2>/dev/null; pgrep -af 'glorytun.*udp|gt-udp' | head
echo DONE
