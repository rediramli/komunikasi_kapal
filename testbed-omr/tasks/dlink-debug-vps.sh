F=/etc/mediamtx/mediamtx.yml
sed -i '/10.255.252.2:18554\/live\/profile.0/{n;n;s/sourceOnDemand: yes/sourceOnDemand: no/}' $F
grep -A3 '^  dlink:' $F | sed 's/admin:[^@]*@/admin:***@/'
systemctl restart mediamtx; sleep 15
journalctl -u mediamtx --since "-1min" --no-pager | sed 's/admin:[^@]*@/admin:***@/' | grep -iE 'dlink|ERR|WAR'
