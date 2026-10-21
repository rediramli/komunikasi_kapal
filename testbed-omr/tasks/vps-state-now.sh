echo "== source dlink"; grep -A2 '^  dlink' /etc/mediamtx/mediamtx.yml | sed 's/admin:[^@]*@/admin:***@/'
echo "== aturan expose / DNAT publik"; nft list ruleset | grep -nE 'dnat|18554|8554|expose' | head -15
echo "== log mediamtx"; journalctl -u mediamtx -n 8 --no-pager | sed 's/admin:[^@]*@/admin:***@/' | grep -iE 'dlink|ERR' | tail -5
