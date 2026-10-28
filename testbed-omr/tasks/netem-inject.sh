# Inject a maritime condition on ONE WAN with tc netem, with MANDATORY auto-restore.
# Runs on the RPi:  ssh ... 'sh -s <SCN> <dev> <secs>' < tasks/netem-inject.sh
#   SCN  : S0 S1 S2 S3 S4 S5 S6   (catalogue below)
#   dev  : wan1 (Simba) | wan2 (Singtel)
#   secs : auto-restore after this many seconds (default 60, clamped 5..600)
#
# Scenario catalogue (calibrated against PSA Agility drive-test ranges:
# Singtel p50 26ms / p90 35ms, Simba demoted 14% of time, RTT p99 ~1234ms, loss up to 66%):
#   S0 port, good (reference)      : (no impairment)
#   S1 near coast, light           : delay 30ms 10ms loss 0.5%
#   S2 congested port              : delay 80ms 30ms loss 2%  rate 5mbit
#   S3 offshore, weak              : delay 150ms 50ms loss 5% rate 2mbit
#   S4 cell edge (cell-hopping)    : delay 300ms 100ms loss 10% rate 1mbit
#   S5 total drop                  : loss 100%        (prefer the dashboard Cut; see GUARD)
#   S6 GEO VSAT, high latency      : delay 600ms 40ms loss 1% rate 5mbit
SCN=${1:-S0}; DEV=${2:-wan1}; SECS=${3:-60}
[ "$DEV" = wan1 ] || [ "$DEV" = wan2 ] || { echo "ERR dev must be wan1|wan2"; exit 1; }
SECS=$(awk -v s="$SECS" 'BEGIN{s=s+0; if(s<5)s=5; if(s>600)s=600; print int(s)}')
OTHER=$([ "$DEV" = wan1 ] && echo wan2 || echo wan1)

# Control-plane guard: the OpenVPN tunnel (and Tailscale/SSH) rides BOTH WANs, so
# degrading one is safe but degrading both can freeze control. Refuse if the other
# WAN already has netem, and refuse the total-drop scenario here (use the dashboard
# Cut, which drops data but keeps the router's own control path and auto-restores).
if tc qdisc show dev "$OTHER" 2>/dev/null | grep -q netem; then
  echo "GUARD: $OTHER already impaired; refusing to degrade BOTH WANs (control plane). Clear it first."; exit 1
fi
if [ "$SCN" = S5 ]; then
  echo "GUARD: S5 (loss 100%) can stall the tunnel that carries control. Use the dashboard 'Cut $DEV' instead (tested, auto-restores)."; exit 1
fi

case "$SCN" in
  S0) P="" ;;
  S1) P="delay 30ms 10ms loss 0.5%" ;;
  S2) P="delay 80ms 30ms loss 2% rate 5mbit" ;;
  S3) P="delay 150ms 50ms loss 5% rate 2mbit" ;;
  S4) P="delay 300ms 100ms loss 10% rate 1mbit" ;;
  S6) P="delay 600ms 40ms loss 1% rate 5mbit" ;;
  *)  echo "ERR unknown scenario '$SCN'"; exit 1 ;;
esac

tc qdisc del dev "$DEV" root 2>/dev/null
if [ -n "$P" ]; then
  tc qdisc add dev "$DEV" root netem $P || { echo "ERR netem apply failed on $DEV"; exit 1; }
fi
ID=$(date +%s); echo "$ID" > /tmp/netem_$DEV.id
# mandatory auto-restore, detached so an SSH/control blip can't leave it stuck
setsid sh -c "sleep $SECS; [ \"\$(cat /tmp/netem_$DEV.id 2>/dev/null)\" = $ID ] && { tc qdisc del dev $DEV root 2>/dev/null; rm -f /tmp/netem_$DEV.id; logger -t netem \"auto-restore $DEV\"; }" </dev/null >/dev/null 2>&1 &
echo "APPLIED $SCN on $DEV: netem ${P:-<none>}  (auto-restore in ${SECS}s)"
echo "now: $(tc qdisc show dev $DEV | head -1)"
