# mediamtx-log.sh (VPS) - kapan stream live/cam tersambung / putus (bukti dari sisi server)
journalctl -u mediamtx --since "40 min ago" --no-pager | grep -iE 'publish|is reading|closed|destroyed|error|timeout' | tail -60
