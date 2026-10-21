# result-auto-test.sh - tampilkan ringkasan tes terakhir
D=$(ls -dt /root/fotest_*/ 2>/dev/null | head -1)
[ -f "$D/done" ] || echo "!! tes belum selesai ($D)"
cat "$D/summary.txt" 2>/dev/null; echo; cat "$D/marks.csv"; echo; tail -3 "$D/subflows.csv"
nft list table inet fotest >/dev/null 2>&1 && echo "!! tabel fotest masih ada" || echo "link normal (tabel fotest sudah dihapus)"
