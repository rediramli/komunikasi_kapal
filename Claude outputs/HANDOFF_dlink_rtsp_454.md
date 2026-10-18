# Handoff: Kamera D-Link DCS-8526LH → MediaMTX VPS lewat tunnel MPTCP (masalah RTSP 454)

Instruksi untuk Claude Code yang berjalan di PC **REDLAB**, di repo `~/fssd-proj-2-3/testbed-omr/`.
Tujuan: stream kamera D-Link bisa ditonton dari `rtsp://168.144.105.155:8554/dlink` (VLC) dan, kalau codec-nya H.264, juga dari `http://168.144.105.155:8888/dlink` (HLS).

---

## 1. Aturan keamanan (wajib)

- **PIN kamera tidak boleh muncul di chat, log, command line, atau git.** User yang mengetik PIN sendiri lewat prompt (`stty -echo; read P`). Setiap output yang bisa berisi URL kamera harus disaring dengan `sed 's/admin:[^@]*@/admin:***@/'`.
- Jangan commit `openmptcprouter_config.txt`, key, atau `mediamtx.yml`.
- Jangan pernah membuat port forward uci dengan `src='vpn'` di RPi. OMR **otomatis menyalinnya ke VPS** sebagai DNAT publik, sehingga kamera terbuka ke internet. Kejadian ini sudah terjadi sekali dan sudah diperbaiki.
- Jangan mengubah `ovpn-guard`, pengaturan MPTCP, scheduler, atau OMR tanpa persetujuan user.

## 2. Akses

| Host | Cara akses | Catatan |
|---|---|---|
| RPi4 OMR | `./run.sh rpi tasks/x.sh` atau `ssh root@100.102.109.59` (Tailscale) | OpenWrt baru: package manager **`apk`** (bukan opkg). **Tidak ada ffmpeg/ffprobe** dan tidak tersedia di repo. Ada `curl`, `openssl`, GNU `nc` |
| VPS DO `omr-vps` | `./run.sh vps tasks/x.sh` atau `ssh -p 65222 root@168.144.105.155` | SSH **port 65222**, bukan 22. Debian, ada python3, **tidak ada ffmpeg/ffprobe** |
| REDLAB | lokal | Ada `ffprobe` (ffmpeg 6.x) |

- `run.sh` mengirim script lewat `ssh ... 'sh -s'`, jadi **stdin terpakai untuk isi script**. Script yang meminta input (PIN) harus disalin dulu ke host (`scp -O` untuk RPi/dropbear, `scp -P 65222` untuk VPS), lalu dijalankan dengan `ssh -t`.
- Terminal user sering merusak baris panjang saat paste. Buat file lewat Write tool atau scp, jangan menyuruh user mem-paste baris lebih dari sekitar 80 karakter.

## 3. Topologi yang relevan

```
Kamera D-Link 192.168.110.2 (RTSP :554, ONVIF :80)
   │  (LAN Ruijie 192.168.110.0/24, gw 192.168.110.1; Ruijie WAN = 192.168.100.203)
   │  RPi punya rute langsung: 192.168.110.0/24 dev eth0 (TCP RPi→kamera terbukti jalan)
RPi4 OMR  LAN 192.168.100.1 · tunnel OpenVPN 10.255.252.2 (zona fw 'vpn', network omrvpn)
   │  OpenVPN = 1 koneksi MPTCP, 2 subflow (wan1 Simba 192.168.1.100, wan2 Singtel 192.168.2.100)
VPS 168.144.105.155 · tun0 10.255.252.1 · rute 192.168.100.0/24 via 10.255.252.2
   MediaMTX: /usr/local/bin/mediamtx /etc/mediamtx/mediamtx.yml (systemd 'mediamtx')
   RTSP 8554 · HLS 8888 · RTMP 1935 · WebRTC 8889
```

## 4. Kondisi saat ini

**Kamera**
- ONVIF jalan dengan user `admin` + PIN dari label kamera. `GetStreamUri` mengembalikan:
  - main: `rtsp://192.168.110.2/live/profile.0`
  - sub: `rtsp://192.168.110.2/live/profile.1`
- Server RTSP kamera: `Server: RtpRtspServer`. `OPTIONS` dijawab `200 OK` (Public: OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN).
- **Masalahnya:** `DESCRIBE` tanpa login dijawab **`454 Session Not Found`**, bukan `401`. MediaMTX (gortsplib) selalu mengirim DESCRIBE tanpa login dulu dan menunggu tantangan 401, sehingga gagal.

**RPi** (sudah diterapkan, persisten lewat uci include fw4)
- `/etc/dlink/dnat.nft` (chain dstnat): `ip saddr 10.255.252.1 tcp dport 18554 dnat ip to 192.168.110.2:554`
- `/etc/dlink/fwd.nft` (chain forward): `ip saddr 10.255.252.1 ip daddr 192.168.110.2 tcp dport 554 accept`
- `/etc/dlink/snat.nft` (chain srcnat): `ip saddr 10.255.252.1 ip daddr 192.168.110.2 tcp dport 554 masquerade`
- Section uci: `firewall.dlinkinc_dnat`, `firewall.dlinkinc_fwd`, `firewall.dlinkinc_snat` (type nftables, position chain-pre).
- Terbukti dari VPS: `OPTIONS` ke `10.255.252.2:18554` dijawab `200 OK` oleh kamera.

**VPS**
- Di akhir `mediamtx.yml` (di bawah `paths:` / `all_others:`) ada dua path: `dlink` (profile.0) dan `dlink_sub` (profile.1). Source keduanya `rtsp://admin:<PIN>@10.255.252.2:18554/live/profile.N`, dengan `rtspTransport: tcp`.
- `dlink` **sementara** memakai `sourceOnDemand: no` untuk debug. Kembalikan ke `yes` setelah selesai. `dlink_sub` masih `yes`.
- Ada backup `mediamtx.yml.bak.<waktu>`.
- DNAT publik 8554 buatan OMR sudah hilang (dicek dengan `nft list ruleset | grep 'dnat ip to 10.255.252.2'` → kosong). Pastikan tetap kosong.
- Log saat ini: `ERR [path dlink] [RTSP source] bad status code: 454 (Session Not Found)` setiap 5 detik.

## 5. Langkah 1: cari dialek RTSP yang diterima kamera

Script ini dijalankan di **RPi** secara interaktif karena meminta PIN. Buat file `scripts/rtsptest.sh` di repo dengan isi berikut:

```sh
printf "PIN: "; stty -echo; read P; stty echo; echo
A=$(printf 'admin:%s' "$P" | openssl base64)
H=192.168.110.2
t() {
  echo "== $1"
  printf "$2" | nc -w3 $H 554 | grep -E 'RTSP/|WWW-Auth|m=video|a=rtpmap' | head -4
}
U1="rtsp://$H/live/profile.0"
U2="rtsp://$H:554/live/profile.0"
t "A: tanpa login, url tanpa port" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
t "B: tanpa login, url :554" \
  "DESCRIBE $U2 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
t "C: Basic preemptive, url tanpa port" \
  "DESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: Basic $A\r\n\r\n"
t "D: OPTIONS lalu DESCRIBE satu koneksi" \
  "OPTIONS $U1 RTSP/1.0\r\nCSeq: 1\r\n\r\nDESCRIBE $U1 RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n"
```

Jalankan:

```bash
scp -O scripts/rtsptest.sh root@100.102.109.59:/tmp/
ssh -t root@100.102.109.59 sh /tmp/rtsptest.sh
```

Kalau hasilnya belum jelas, tambahkan variasi lain dengan `User-Agent` (misalnya `User-Agent: LibVLC/3.0` atau `ONVIF`), Basic + URL `:554`, atau path `profile.1`. Untuk menghitung Digest secara manual, ambil realm/nonce dari respons yang memuat `WWW-Authenticate`.

## 6. Langkah 2: perbaikan sesuai hasil

**Kasus C (atau D) berhasil:** kamera butuh login dikirim langsung, atau butuh urutan permintaan tertentu.
- Buat relay RTSP kecil dengan Python3 di VPS, sebagai service systemd `dlink-relay`.
- Relay listen di `127.0.0.1:18555` dan meneruskan ke `10.255.252.2:18554`.
- Untuk arah klien → kamera:
  - Pesan teks (baris pertama berupa method RTSP) diparse, lalu disisipi header `Authorization: Basic ...` dan/atau URL-nya ditulis ulang ke `rtsp://192.168.110.2/...`.
  - Frame interleaved yang diawali byte `$` (format: `$`, channel, panjang 2 byte, data) diteruskan apa adanya.
- Arah kamera → klien diteruskan mentah. Tulis ulang header `Content-Base` dan URL di respons kalau perlu.
- PIN disimpan di `/etc/dlink-relay.env` dengan `chmod 600`. Isinya diketik user lewat prompt, bukan ditulis Claude.
- Ganti source MediaMTX menjadi `rtsp://127.0.0.1:18555/live/profile.0` tanpa kredensial. Hapus PIN dari `mediamtx.yml`.

**Kasus A berhasil tapi B tidak:** kamera mencocokkan URL. Pilihannya:
- Relay seperti di atas, cukup menulis ulang URL saja; atau
- Routing tanpa DNAT. Di VPS: `ip route add 192.168.110.0/24 via 10.255.252.2 dev tun0`, dibuat persisten lewat systemd unit atau `route`/`iroute` OpenVPN (cek dulu cara rute 192.168.100.0/24 dipasang). Di RPi: aturan fwd dan masquerade sudah ada, dan DNAT tidak dipakai lagi. Source MediaMTX menjadi `rtsp://admin:<PIN>@192.168.110.2/live/profile.0`.

**Semua variasi `454`:**
- Coba `profile.1`.
- Cek jam kamera vs RPi.
- Minta user mengecek aplikasi mydlink: pengaturan ONVIF/RTSP, update firmware, atau reboot kamera.
- Sebagai pembanding, coba juga tes langsung dari laptop di LAN Ruijie dengan VLC: `rtsp://admin:PIN@192.168.110.2/live/profile.0`. Ini memastikan RTSP kamera memang bisa dipakai oleh klien standar.

## 7. Langkah 3: verifikasi dan rapikan

1. Dari REDLAB: `ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_name,width,height -of compact rtsp://168.144.105.155:8554/dlink` → harus menampilkan codec dan resolusi.
2. Minta user menonton lewat VLC: `rtsp://168.144.105.155:8554/dlink`. Kalau codec-nya h264, juga lewat browser: `http://168.144.105.155:8888/dlink`.
3. Pastikan video benar-benar lewat MPTCP: di RPi, `ss -tni` / `ip mptcp monitor` memperlihatkan koneksi OpenVPN dengan 2 subflow, dan trafik upload muncul di wan1/wan2.
4. Kembalikan `dlink` ke `sourceOnDemand: yes`, lalu restart mediamtx.
5. `chmod 600 /etc/mediamtx/mediamtx.yml`, kalau service berjalan sebagai root (`systemctl show -p User --value mediamtx` kosong).
6. Pastikan tidak ada DNAT publik ke RPi: `nft list ruleset | grep 'dnat ip to 10.255.252.2'` di VPS harus kosong.
7. Simpan script baru di `tasks/` atau `scripts/`, lalu update `claude/testbed-omr-rpi4-setup.md` di project: bagian kamera D-Link, 454, solusi, dan peringatan sinkronisasi port forward OMR.

## 8. Catatan lain yang masih terbuka (bukan bagian tugas ini)

- Tabel RTT terkoreksi dan perbaikan Grafana belum masuk ke dokumen project.
- Re-key VPS dan ganti password (shadowsocks, Grafana, Wi-Fi AP `PasswordWiFiAnda`) sebelum dipakai di kapal.
- Ide berikutnya: uji Glorytun UDP, tes reboot (persistensi ovpn-guard dan scheduler), dan scheduler BPF custom.
