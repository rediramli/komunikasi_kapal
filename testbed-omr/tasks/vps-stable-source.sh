F=/etc/mediamtx/mediamtx.yml
B=$F.bak.$(date +%Y%m%d_%H%M%S); cp -a "$F" "$B"; echo "backup: $B"
n=$(grep -c '@10.255.252.2:18554' "$F")
echo "occurrences of old host: $n"
sed -i 's/@10\.255\.252\.2:18554/@192.168.100.1:18554/g' "$F"
echo "== dlink block now (masked):"
awk 'NR>=889 && NR<=898' "$F" | sed 's#admin:[^@]*@#admin:***@#'
systemctl restart mediamtx
sleep 2
echo "mediamtx: $(systemctl is-active mediamtx)"
echo DONE
