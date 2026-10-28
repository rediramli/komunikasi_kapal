# Dynamic "voyage" condition: step ONE WAN through a time-varying sequence of
# netem profiles, mimicking a ship sailing through changing coverage. Each phase
# is HELD (re-asserted every 1 s) so OMR's path tracker can't wipe it mid-phase,
# and the whole voyage auto-restores on exit. Runs on the RPi:
#   ssh ... 'sh -s <dev> <voyage>' < tasks/netem-voyage.sh
#     dev    : wan1 (Simba) | wan2 (Singtel)
#     voyage : leaving-port (default) | handover | storm
#
# A voyage is a list of "PROFILE:SECONDS". Profiles reuse the static catalogue:
#   S0 clean · S1 delay 30ms 10ms loss 0.5% · S2 delay 80ms 30ms loss 2% rate 5mbit
#   S3 delay 150ms 50ms loss 5% rate 2mbit · S4 delay 300ms 100ms loss 10% rate 1mbit
#   S6 delay 600ms 40ms loss 1% rate 5mbit
DEV=${1:-wan1}; VOY=${2:-leaving-port}
[ "$DEV" = wan1 ] || [ "$DEV" = wan2 ] || { echo "ERR dev must be wan1|wan2"; exit 1; }
OTHER=$([ "$DEV" = wan1 ] && echo wan2 || echo wan1)
if tc qdisc show dev "$OTHER" 2>/dev/null | grep -q netem; then
  echo "GUARD: $OTHER already impaired; refusing to degrade BOTH WANs. Clear it first."; exit 1
fi

prof() {  # echo the netem args for a profile id
  case "$1" in
    S0) echo "" ;;
    S1) echo "delay 30ms 10ms loss 0.5%" ;;
    S2) echo "delay 80ms 30ms loss 2% rate 5mbit" ;;
    S3) echo "delay 150ms 50ms loss 5% rate 2mbit" ;;
    S4) echo "delay 300ms 100ms loss 10% rate 1mbit" ;;
    S6) echo "delay 600ms 40ms loss 1% rate 5mbit" ;;
    *)  echo "__ERR__" ;;
  esac
}
case "$VOY" in
  # leave the quay, cross a congested harbour, head offshore to the cell edge, then regain coverage
  leaving-port) SEQ="S0:12 S2:22 S3:24 S4:30 S3:20 S1:16 S0:12" ;;
  # repeated brief cell-tower handovers: short hard drops between good spells
  handover)     SEQ="S1:16 S4:8 S1:16 S4:8 S1:16 S4:8 S1:16" ;;
  # a squall: fast ramp into a sustained severe condition, then slow clearing
  storm)        SEQ="S1:12 S3:16 S4:40 S3:18 S2:16 S0:12" ;;
  *) echo "ERR unknown voyage '$VOY' (leaving-port|handover|storm)"; exit 1 ;;
esac

ID=$(date +%s); echo "$ID" > /tmp/netem_$DEV.id
TOTAL=$(echo "$SEQ" | tr ' ' '\n' | awk -F: '{s+=$2} END{print s}')
echo "VOYAGE '$VOY' on $DEV — $TOTAL s total. Phases: $SEQ"
setsid sh -c '
  ID='"$ID"'; DEV='"$DEV"'
  prof() { case "$1" in
    S0) echo "";; S1) echo "delay 30ms 10ms loss 0.5%";; S2) echo "delay 80ms 30ms loss 2% rate 5mbit";;
    S3) echo "delay 150ms 50ms loss 5% rate 2mbit";; S4) echo "delay 300ms 100ms loss 10% rate 1mbit";;
    S6) echo "delay 600ms 40ms loss 1% rate 5mbit";; esac; }
  for step in '"$SEQ"'; do
    scn=${step%%:*}; secs=${step##*:}; P=$(prof "$scn")
    logger -t netem "voyage '"$DEV"' -> $scn (${secs}s)"
    end=$(( $(date +%s) + secs ))
    while [ $(date +%s) -lt $end ] && [ "$(cat /tmp/netem_$DEV.id 2>/dev/null)" = $ID ]; do
      if [ -n "$P" ]; then
        tc qdisc show dev $DEV | grep -q netem || tc qdisc replace dev $DEV root netem $P
      else
        tc qdisc show dev $DEV | grep -q netem && tc qdisc del dev $DEV root 2>/dev/null
      fi
      sleep 1
    done
    [ "$(cat /tmp/netem_$DEV.id 2>/dev/null)" = $ID ] || break
  done
  tc qdisc del dev $DEV root 2>/dev/null; rm -f /tmp/netem_$DEV.id; logger -t netem "voyage '"$DEV"' done"
' </dev/null >/dev/null 2>&1 &
echo "started (detached); auto-restores on completion or if the id file is cleared."
