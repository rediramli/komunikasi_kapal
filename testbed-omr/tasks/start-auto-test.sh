# start-auto-test.sh - mulai tes failover otomatis di RPi (latar belakang, boleh tutup SSH)
nohup sh /root/failover-test.sh ${DUR:-420} auto </dev/null >/root/fotest_last_console.txt 2>&1 &
sleep 6; tr '\r' '\n' < /root/fotest_last_console.txt | grep -v '^\s*\[' | head -20
echo "(berjalan di latar belakang; selesai ±$(( ${DUR:-420}/60 + 1 )) menit lagi)"
