echo "== current /etc/rc.local"
cat /etc/rc.local 2>/dev/null
echo "== add idempotent camera-LAN address line before 'exit 0'"
L='ip addr add 192.168.110.250/24 dev eth0 2>/dev/null  # camera LAN reach (persist)'
if grep -q '192.168.110.250/24 dev eth0' /etc/rc.local 2>/dev/null; then
  echo "(already present in rc.local)"
else
  # insert before exit 0 if present, else append
  if grep -q '^exit 0' /etc/rc.local 2>/dev/null; then
    sed -i "s|^exit 0|$L\nexit 0|" /etc/rc.local
  else
    printf '%s\n' "$L" >> /etc/rc.local
  fi
  echo "added."
fi
echo "== rc.local now:"
cat /etc/rc.local
echo DONE
