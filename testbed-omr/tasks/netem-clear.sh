# Remove tc netem from a WAN (or both). Runs on the RPi.
#   ssh ... 'sh -s <wan1|wan2|all>' < tasks/netem-clear.sh
D=${1:-all}
for dev in wan1 wan2; do
  [ "$D" = all ] || [ "$D" = "$dev" ] || continue
  rm -f /tmp/netem_$dev.id
  if tc qdisc show dev "$dev" 2>/dev/null | grep -q netem; then
    tc qdisc del dev "$dev" root 2>/dev/null && echo "cleared netem on $dev"
  else
    echo "$dev: no netem"
  fi
done
