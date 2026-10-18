echo "== 1. No public DNAT to RPi tunnel (must be EMPTY):"
nft list ruleset 2>/dev/null | grep 'dnat ip to 10.255.252.2' || echo "  (empty - good)"
echo
echo "== 2. mediamtx service user (empty = root):"
systemctl show -p User --value mediamtx
echo
echo "== 3. secure mediamtx.yml perms"
chmod 600 /etc/mediamtx/mediamtx.yml
ls -l /etc/mediamtx/mediamtx.yml
echo
echo "== 4. list mediamtx backups"
ls -1 /etc/mediamtx/mediamtx.yml.bak.* 2>/dev/null | tail -5
echo DONE
