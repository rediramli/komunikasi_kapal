#!/bin/sh
# Guided demo: walk Simba (wan1) through S0->S6, then the dynamic "leaving-port"
# voyage B. Each phase is HELD by re-asserting every 1s (so OMR can't wipe it);
# the whole run auto-restores on exit. Singtel (wan2) stays healthy as reference.
DEV=wan1
trap 'tc qdisc del dev $DEV root 2>/dev/null; echo "[`date +%T`] cleared" ' EXIT INT TERM
hold() {  # $1=netem-args ("" = clean)  $2=seconds  $3=label
  logger -t demo "$3"
  echo "[`date +%T`] >>> $3  (${2}s)"
  end=$(( `date +%s` + $2 ))
  while [ `date +%s` -lt $end ]; do
    if [ -n "$1" ]; then
      tc qdisc show dev $DEV 2>/dev/null | grep -q netem || tc qdisc replace dev $DEV root netem $1
    else
      tc qdisc show dev $DEV 2>/dev/null | grep -q netem && tc qdisc del dev $DEV root 2>/dev/null
    fi
    sleep 1
  done
}
echo "===== STATIC WALK S0 -> S6 (Simba degraded, Singtel healthy) ====="
hold ""                                    15 "S0 baseline (clean)"
hold "delay 30ms 10ms loss 0.5%"           25 "S1 near coast (light)"
hold "delay 80ms 30ms loss 2% rate 5mbit"  25 "S2 congested port"
hold "delay 150ms 50ms loss 5% rate 2mbit" 25 "S3 offshore (weak)"
hold "delay 300ms 100ms loss 10% rate 1mbit" 30 "S4 cell edge (severe)"
hold "delay 600ms 40ms loss 1% rate 5mbit" 25 "S6 GEO VSAT (high latency)"
hold ""                                    12 "recovery (clean)"
echo "===== DYNAMIC VOYAGE B: leaving-port ====="
hold ""                                    10 "B0 alongside"
hold "delay 80ms 30ms loss 2% rate 5mbit"  20 "B: congested harbour (S2)"
hold "delay 150ms 50ms loss 5% rate 2mbit" 22 "B: offshore weak (S3)"
hold "delay 300ms 100ms loss 10% rate 1mbit" 28 "B: cell edge (S4)"
hold "delay 150ms 50ms loss 5% rate 2mbit" 18 "B: re-acquiring (S3)"
hold "delay 30ms 10ms loss 0.5%"           15 "B: near coast (S1)"
hold ""                                    12 "B: back in range (S0)"
echo "[`date +%T`] ===== DEMO COMPLETE ====="
