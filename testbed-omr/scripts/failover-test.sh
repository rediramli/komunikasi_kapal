#!/bin/sh
# failover-test.sh - uji failover MPTCP dua link saat streaming kamera (testbed OMR RPi4)
#
# Jalankan di RPi OMR:   sh /root/failover-test.sh [durasi_detik]      (default 600)
# Kalau SSH putus:       login lagi, lalu  sh /root/failover-test.sh view
# Hasil:                 /root/fotest_<waktu>/  dan  /root/fotest_<waktu>.tar.gz
#
# Yang direkam (semua di latar belakang, tetap jalan walau SSH putus):
#   traffic.csv   upload per link tiap detik + status up/down menurut OMR
#   subflows.csv  jumlah subflow proxy per link tiap 5 detik (+ yang masih lewat VPN)
#   mptcp_mon.log event MPTCP (subflow dibuat/ditutup) dengan jam
#   marks.csv     waktu Anda menekan ENTER (= saat benar-benar cabut/colok)
#   summary.txt   ringkasan otomatis: macet terpanjang & waktu deteksi OMR per kejadian
#
# Mode OTOMATIS (tanpa cabut kabel; putus sinyal disimulasikan dengan nftables):
#   sh failover-test.sh 420 auto        -> Singtel down 30s, up 120s, Simba down 210s, up 300s
#   Boleh tutup SSH; semua jalan di latar belakang. Link dipulihkan otomatis di akhir (+failsafe).
#   Darurat (pulihkan semua link):  nft delete table inet fotest
#
# Jadwal bisa diubah lewat env, mis.:
#   PLAN="30|CABUT RUTM16 (Singtel);120|COLOK RUTM16 (Singtel)" sh failover-test.sh 240

DUR=${DUR:-600}
W1=${W1:-wan1}; N1=${N1:-Simba}
W2=${W2:-wan2}; N2=${N2:-Singtel}
PLAN=${PLAN:-"60|CABUT RUTM30 ($N1);180|COLOK RUTM30 ($N1);300|CABUT RUTM16 ($N2);420|COLOK RUTM16 ($N2)"}
STALL_KBPS=${STALL_KBPS:-500}   # total upload di bawah ini = dianggap macet

txb() { cat /sys/class/net/$1/statistics/tx_bytes 2>/dev/null || echo 0; }
st()  { uci -q get openmptcprouter.$1.state || echo '?'; }

# --- Simulasi putus sinyal seluler (mode otomatis) ---------------------------------
# Membuang semua paket lewat wanX KECUALI ke subnet router Teltonika-nya, jadi interface
# tetap up dan gateway tetap bisa di-ping - mirip sinyal seluler hilang. Tabel nft
# terpisah (inet fotest) sehingga tidak mengganggu firewall OMR; dihapus otomatis.
lnet() { ip route show dev $1 proto kernel 2>/dev/null | awk 'NR==1{print $1}'; }
link_down() {
  i=$1; net=$(lnet $i); [ -n "$net" ] || net=0.0.0.0/32
  nft add table inet fotest
  nft "add chain inet fotest pre_$i { type filter hook prerouting priority -300; policy accept; }"
  nft "add chain inet fotest post_$i { type filter hook postrouting priority -300; policy accept; }"
  nft add rule inet fotest pre_$i iifname "$i" ip saddr != $net drop
  nft add rule inet fotest post_$i oifname "$i" ip daddr != $net drop
}
link_up() {
  i=$1
  for c in pre_$i post_$i; do nft flush chain inet fotest $c 2>/dev/null; nft delete chain inet fotest $c 2>/dev/null; done
}
auto_actions() {
  D=$1; start=$(cat $D/start)
  echo "$PLAN" | tr ';' '\n' | while IFS='|' read off lab; do
    [ -n "$off" ] || continue
    act=$(echo "$lab" | sed -n 's/.*\[auto: *\([A-Z]*\) *\([a-z0-9]*\)\].*/\1 \2/p')
    [ -n "$act" ] || continue
    w=$((start+off-$(date +%s))); [ $w -gt 0 ] && sleep $w
    set -- $act
    if [ "$1" = DOWN ]; then link_down $2; else link_up $2; fi
    echo "$(date +%s),$(date +%T),AUTO $1 $2" >> $D/marks.csv
  done
}

precheck() {
  echo "== Pre-check"
  p=$(uci -q get shadowsocks-rust.hivpn.server)
  v=$(ss -tn 2>/dev/null | grep -c '10.255.247.1:65280')
  echo "  proxy hivpn -> ${p:-(tidak ada)}   koneksi proxy lewat VPN: $v"
  echo "  $N1 ($W1): $(st $W1)   $N2 ($W2): $(st $W2)"
  a=$(txb $W1); b=$(txb $W2); sleep 3; c=$(txb $W1); d=$(txb $W2)
  r=$(( ((c-a)+(d-b))*8/3000 ))
  echo "  upload saat ini: $r kbps ($N1 $(( (c-a)*8/3000 )) / $N2 $(( (d-b)*8/3000 )))"
  warn=0
  [ "$p" = "mptcpovervpn" ] && { echo "  !! proxy masih lewat VPN (hivpn -> mptcpovervpn)"; warn=1; }
  [ "$r" -lt 1000 ] && { echo "  !! stream sepertinya belum jalan (< 1000 kbps)"; warn=1; }
  if [ $warn = 1 ]; then printf "Tetap lanjut? [y/N] "; read ans; [ "$ans" = y ] || exit 1; fi
}

bg() {
  D=$1; start=$(cat $D/start); end=$((start+DUR))
  if echo "$PLAN" | grep -q '\[auto:'; then
    ( sleep $((DUR+20)); nft delete table inet fotest 2>/dev/null ) &      # failsafe: semua link pulih
    auto_actions $D &
  fi
  ( echo "epoch,time,${N1}_kbps,${N2}_kbps,total_kbps,${N1}_state,${N2}_state" > $D/traffic.csv
    a=$(txb $W1); b=$(txb $W2)
    while [ $(date +%s) -lt $end ]; do
      sleep 1
      c=$(txb $W1); d=$(txb $W2)
      x=$(( (c-a)*8/1000 )); y=$(( (d-b)*8/1000 )); a=$c; b=$d
      echo "$(date +%s),$(date +%T),$x,$y,$((x+y)),$(st $W1),$(st $W2)" >> $D/traffic.csv
    done ) &
  IP1=$(uci -q get network.$W1.ipaddr); IP2=$(uci -q get network.$W2.ipaddr)
  ( echo "time,${N1}_subflows,${N2}_subflows,via_vpn,openvpn_sf_${N1}/${N2}" > $D/subflows.csv
    while [ $(date +%s) -lt $end ]; do
      s=$(ss -tan 2>/dev/null | grep ESTAB)
      echo "$(date +%T),$(echo "$s" | grep -c "$IP1[%:].*:6528[0-9]\|$IP1[%:].*:65301"),$(echo "$s" | grep -c "$IP2[%:].*:6528[0-9]\|$IP2[%:].*:65301"),$(echo "$s" | grep -c '10.255.247.1:65280'),$(echo "$s" | grep "$IP1[%:].*:65301" | wc -l)/$(echo "$s" | grep "$IP2[%:].*:65301" | wc -l)" >> $D/subflows.csv
      sleep 5
    done ) &
  ip mptcp monitor 2>/dev/null | while read l; do echo "$(date +%T) $l"; done > $D/mptcp_mon.log &
  left=$((end - $(date +%s))); [ $left -gt 0 ] && sleep $left
  sleep 3
  kill $(pgrep -f 'ip mptcp monitor') 2>/dev/null
  nft delete table inet fotest 2>/dev/null
  sleep 1
  analyze $D > $D/summary.txt 2>&1
  tar czf $D.tar.gz -C /root $(basename $D) 2>/dev/null
  touch $D/done
}

analyze() {
  D=$1; start=$(cat $D/start)
  echo "Ringkasan tes failover - mulai $(cat $D/start_hms) (jam router), durasi ${DUR} s, ambang macet < ${STALL_KBPS} kbps"
  echo "$PLAN" | tr ';' '\n' > $D/plan.txt
  awk -F, -v start=$start -v stall=$STALL_KBPS -v n1="$N1" -v n2="$N2" '
    FILENAME==ARGV[1] { if ($0=="") next; split($0,p,"|"); ne++; off[ne]=p[1]; lab[ne]=p[2]; next }
    FILENAME==ARGV[2] { if ($1!="") { nm++; mk[nm]=$1 }; next }
    FNR>1 { n++; e[n]=$1; h[n]=$2; tot[n]=$5; s[1,n]=$6; s[2,n]=$7 }
    END {
      printf "%-26s %-9s %-8s %-18s %s\n", "Kejadian", "Jam", "Sumber", "Macet terpanjang", "Deteksi OMR"
      for (k=1; k<=ne; k++) {
        T[k]=start+off[k]; S[k]="jadwal"; bd=46
        for (m=1; m<=nm; m++) { dd=mk[m]-T[k]; if (dd<0) dd=-dd; if (dd<bd) { bd=dd; best=mk[m] } }
        if (bd<=45) { T[k]=best; S[k]="ENTER" }
      }
      for (k=1; k<=ne; k++) {
        te=T[k]; src=S[k]
        wend = (k<ne) ? T[k+1]-3 : te+150; if (wend>te+150) wend=te+150
        link = index(lab[k],n1) ? 1 : (index(lab[k],n2) ? 2 : 0)
        want = index(lab[k],"CABUT") ? "down" : "up"
        cur=0; mx=0; det=-1; hm="-"
        for (i=1; i<=n; i++) {
          if (e[i]<te-3 || e[i]>=wend) continue
          if (hm=="-" && e[i]>=te) hm=h[i]
          if (tot[i]<stall) { cur++; if (cur>mx) mx=cur } else cur=0
          if (det<0 && link && e[i]>=te && s[link,i]==want) det=e[i]-te
        }
        printf "%-26s %-9s %-8s %-18s %s\n", lab[k], hm, src, mx " s", (det<0 ? "-" : want " setelah " det " s")
      }
      bad=0; for (i=1;i<=n;i++) if (tot[i]<stall) bad++
      printf "\nTotal detik macet selama tes: %d dari %d s\n", bad, n
    }' $D/plan.txt $D/marks.csv $D/traffic.csv
  echo
  echo "Subflow proxy per link (awal / min / akhir):"
  awk -F, 'NR>1 { n++; for (c=2;c<=4;c++) { if (n==1) { f[c]=$c; mn[c]=$c } ; if ($c<mn[c]) mn[c]=$c; l[c]=$c } }
    END { printf "  %s: %s / %s / %s   %s: %s / %s / %s   lewat VPN: %s / %s / %s\n", n1, f[2],mn[2],l[2], n2, f[3],mn[3],l[3], f[4],mn[4],l[4] }' n1="$N1" n2="$N2" $D/subflows.csv
}

view() {
  D=$1; [ -d "$D" ] || { echo "Folder tes tidak ditemukan"; exit 1; }
  start=$(cat $D/start)
  trap 'echo; echo "Tampilan ditutup - perekaman TETAP jalan. Lihat lagi: sh $0 view"; exit 0' INT
  echo "Folder: $D"
  echo "Tekan ENTER tepat saat Anda benar-benar mencabut/mencolok router (dicatat sebagai MARK)."
  echo "Ctrl+C hanya menutup tampilan; perekaman tetap jalan."
  echo "Jadwal:"; echo "$PLAN" | tr ';' '\n' | while IFS='|' read off lab; do printf "  menit %d:%02d  %s\n" $((off/60)) $((off%60)) "$lab"; done
  echo
  while [ ! -f $D/done ]; do
    now=$(date +%s); el=$((now-start))
    echo "$PLAN" | tr ';' '\n' | while IFS='|' read off lab; do
      if [ -n "$off" ] && [ $el -ge $off ] && [ ! -f $D/.shown_$off ]; then
        touch $D/.shown_$off
        printf "\a\n\n  >>>>>>  [%s]  SEKARANG: %s  (tekan ENTER saat dilakukan)  <<<<<<\n\n" "$(date +%T)" "$lab"
      fi
    done
    if [ $el -le $DUR ]; then
      IFS=, read -r ep hm x y t s1 s2 <<EOF
$(tail -1 $D/traffic.csv 2>/dev/null)
EOF
      printf "\r  [%02d:%02d] %s %5s kbps (%s) | %s %5s kbps (%s) | total %5s   " $((el/60)) $((el%60)) "$N1" "$x" "$s1" "$N2" "$y" "$s2" "$t"
    else
      printf "\r  merangkum hasil...                                                            "
    fi
    prev=$(date +%s)
    if read -t 1 k 2>/dev/null; then
      echo "$(date +%s),$(date +%T),MARK" >> $D/marks.csv; echo "  >> MARK dicatat $(date +%T)"
    else
      [ "$(date +%s)" = "$prev" ] && sleep 1
    fi
  done
  echo; echo; cat $D/summary.txt
  echo; echo "Arsip: $D.tar.gz"
  echo "Ambil ke laptop (PowerShell):  scp -O root@100.102.109.59:$D.tar.gz ."
}

if [ "${2:-}" = auto ] && [ -z "${PLAN_SET:-}" ]; then
  PLAN="30|CABUT $N2 [auto: DOWN $W2];120|COLOK $N2 [auto: UP $W2];210|CABUT $N1 [auto: DOWN $W1];300|COLOK $N1 [auto: UP $W1]"
fi
case "$1" in
  _bg)  DUR=$3; bg "$2"; exit 0 ;;
  view) view "$(ls -dt /root/fotest_* 2>/dev/null | grep -v '\.tar\.gz$' | head -1)"; exit 0 ;;
  *[!0-9]*) echo "Pakai: sh $0 [durasi_detik] [auto] | view"; exit 1 ;;
  ?*)   DUR=$1 ;;
esac

precheck
D=/root/fotest_$(date +%Y%m%d_%H%M%S); mkdir -p $D
date +%s > $D/start; date +%T > $D/start_hms; : > $D/marks.csv
echo "$PLAN" | tr ';' '\n' > $D/plan.txt
export DUR W1 W2 N1 N2 PLAN STALL_KBPS
nohup sh "$0" _bg "$D" "$DUR" >/dev/null 2>&1 &
view "$D"
