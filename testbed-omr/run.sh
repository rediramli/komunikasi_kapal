#!/usr/bin/env bash
# run.sh - jalankan skrip tugas di RPi OMR atau VPS dari REDLAB; output disimpan di logs/
# Pakai:  ./run.sh rpi tasks/audit-rpi.sh      ./run.sh vps tasks/xxx.sh
# Skrip dikirim lewat stdin (ssh ... 'sh -s'), jadi tidak ada masalah paste.
set -u
D=$(cd "$(dirname "$0")" && pwd)
case "${1:-}" in
  rpi) HOST=(root@100.102.109.59) ;;
  vps) HOST=(-p 65222 root@168.144.105.155) ;;
  *) echo "pakai: $0 rpi|vps tasks/<nama>.sh"; exit 1 ;;
esac
T=${2:?pakai: $0 rpi|vps tasks/<nama>.sh}
mkdir -p "$D/logs"
LOG="$D/logs/$1_$(basename "$T" .sh)_$(date +%Y%m%d_%H%M%S).log"
echo "== $T -> $1   (log: $LOG)"
ssh -o ConnectTimeout=10 "${HOST[@]}" 'sh -s' < "$D/$T" 2>&1 | tee "$LOG"
echo "== selesai. Log: $LOG"
