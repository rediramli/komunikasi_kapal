# Replay a REAL link trace as time-varying netem (the "D10" test). Reads a trace
# CSV already placed on the RPi at /tmp/netem_trace.csv with header:
#   step,rtt_ms,loss_pct,up      (one row per real sample; rtt_ms<0 or up=0 = demoted)
# Each sample is mapped to a netem profile and HELD for STEP seconds (re-asserted
# every 1 s so OMR can't wipe it), compressing the real ~36 s cadence. The whole
# replay auto-restores on exit.  Runs on the RPi:
#   ssh ... 'sh -s <dev> <step_secs>' < tasks/netem-replay.sh
# Mapping (testbed Simba baseline ~15 ms): delay = max(0, rtt-15) ms; loss = loss_pct;
# a demoted sample (up=0 or rtt<0 or loss>=100) becomes loss 100% (total drop).
DEV=${1:-wan1}; STEP=${2:-3}; BASE=15; TRACE=/tmp/netem_trace.csv
[ "$DEV" = wan1 ] || [ "$DEV" = wan2 ] || { echo "ERR dev must be wan1|wan2"; exit 1; }
[ -r "$TRACE" ] || { echo "ERR $TRACE not found (scp the trace first)"; exit 1; }
OTHER=$([ "$DEV" = wan1 ] && echo wan2 || echo wan1)
if tc qdisc show dev "$OTHER" 2>/dev/null | grep -q netem; then
  echo "GUARD: $OTHER already impaired; refusing to degrade BOTH WANs. Clear it first."; exit 1
fi

# Pre-compute "secs<TAB>netem-args" per sample into a steps file (float-safe via awk).
STEPFILE=/tmp/netem_steps.txt
awk -F, -v base="$BASE" -v step="$STEP" 'NR>1 && NF>=4 {
  rtt=$2+0; loss=$3+0; up=$4+0;
  if (up==0 || rtt<0 || loss>=100) { p="loss 100%" }
  else { d=rtt-base; if(d<0)d=0; p="delay " d "ms"; if(loss>0){ p=p " loss " loss "%" } }
  print step "\t" p
}' "$TRACE" > "$STEPFILE"
NSTEP=$(wc -l < "$STEPFILE"); TOTAL=$(( NSTEP * STEP ))
echo "REPLAY '$TRACE' on $DEV: $NSTEP samples x ${STEP}s = ${TOTAL}s (auto-restore on exit)"

ID=$(date +%s); echo "$ID" > /tmp/netem_$DEV.id
setsid sh -c '
  ID='"$ID"'; DEV='"$DEV"'; STEPFILE='"$STEPFILE"'
  while IFS="	" read secs p; do
    [ "$(cat /tmp/netem_$DEV.id 2>/dev/null)" = $ID ] || break
    logger -t netem "replay $DEV -> [$p] ${secs}s"
    end=$(( $(date +%s) + secs ))
    while [ $(date +%s) -lt $end ] && [ "$(cat /tmp/netem_$DEV.id 2>/dev/null)" = $ID ]; do
      tc qdisc show dev $DEV | grep -q netem || tc qdisc replace dev $DEV root netem $p
      sleep 1
    done
  done < "$STEPFILE"
  tc qdisc del dev $DEV root 2>/dev/null; rm -f /tmp/netem_$DEV.id; logger -t netem "replay $DEV done"
' </dev/null >/dev/null 2>&1 &
echo "started (detached)."
