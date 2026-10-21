echo "== nc tersedia?"; which nc; nc 2>&1 | head -3
echo "== Route ke 192.168.110.x"; ip route get 192.168.110.10
echo "== Ping sweep 192.168.110.0/24"
for i in $(seq 2 254); do ping -c1 -W1 192.168.110.$i >/dev/null 2>&1 && echo "  hidup: 192.168.110.$i" & done; wait
echo "== Cek port 554 (cara lain)"
for ip in $(ip neigh | awk '/192.168.110/{print $1}'); do
  (echo > /dev/null | timeout 2 nc $ip 554 </dev/null >/dev/null 2>&1 && echo "  $ip:554 terbuka") 
done
ip neigh | grep 192.168.110
