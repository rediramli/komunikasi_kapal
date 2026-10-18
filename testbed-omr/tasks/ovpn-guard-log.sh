# ovpn-guard-log.sh - riwayat aksi penjaga + kondisi tunnel
logread | grep ovpn-guard | tail -10; echo ---; ss -tan | grep ESTAB | grep ':65301'; ip -br addr show tun0
