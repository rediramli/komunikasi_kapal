printf "RTSP password for admin (yang tadi berhasil): "; stty -echo; read PW; stty echo; echo
F=/etc/mediamtx/mediamtx.yml
B=$F.bak.$(date +%Y%m%d_%H%M%S); cp -a "$F" "$B"; echo "backup: $B"
PW="$PW" python3 - "$F" <<'PY'
import os,sys,re,urllib.parse
f=sys.argv[1]
pw=os.environ['PW']
enc=urllib.parse.quote(pw, safe='')   # URL-encode for safety in the rtsp:// URL
s=open(f).read()
n=s.count('@10.255.252.2:18554')
s2=re.sub(r'(rtsp://admin:)[^@]*(@10\.255\.252\.2:18554)',
          lambda m: m.group(1)+enc+m.group(2), s)
open(f,'w').write(s2)
print("source lines updated:", n)
PY
systemctl restart mediamtx
sleep 2
echo "mediamtx:"; systemctl is-active mediamtx
echo "== dlink block (password masked):"
awk 'NR>=889 && NR<=898' "$F" | sed 's#admin:[^@]*@#admin:***@#'
echo DONE
