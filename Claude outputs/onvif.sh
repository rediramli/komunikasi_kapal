#!/bin/sh
# onvif.sh - tanya URL RTSP resmi ke kamera lewat ONVIF
# Pakai: sh onvif.sh [ip] [port]     (default 192.168.110.2 80)
IP=${1:-192.168.110.2}
PORT=${2:-80}
U=admin

which curl >/dev/null || { echo "perlu curl: opkg install curl"; exit 1; }
which openssl >/dev/null || { echo "perlu: opkg install openssl-util"; exit 1; }

printf "PIN kamera: "
stty -echo; read P; stty echo; echo

W=http://docs.oasis-open.org/wss/2004/01
WSSE=$W/oasis-200401-wss-wssecurity-secext-1.0.xsd
WSU=$W/oasis-200401-wss-wssecurity-utility-1.0.xsd
PWT=$W/oasis-200401-wss-username-token-profile-1.0#PasswordDigest
B64=$W/oasis-200401-wss-soap-message-security-1.0#Base64Binary
ENV=http://www.w3.org/2003/05/soap-envelope
DEV=http://www.onvif.org/ver10/device/wsdl
MED=http://www.onvif.org/ver10/media/wsdl
SCH=http://www.onvif.org/ver10/schema
CT='Content-Type: application/soap+xml; charset=utf-8'

soap() {
  head -c16 /dev/urandom > /tmp/n
  N=$(openssl base64 < /tmp/n)
  C=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  D=$( (cat /tmp/n; printf %s "$C$P") \
       | openssl dgst -sha1 -binary | openssl base64 )
  {
    printf '<?xml version="1.0"?>'
    printf '<s:Envelope xmlns:s="%s"><s:Header>' "$ENV"
    printf '<Security xmlns="%s"><UsernameToken>' "$WSSE"
    printf '<Username>%s</Username>' "$U"
    printf '<Password Type="%s">%s</Password>' "$PWT" "$D"
    printf '<Nonce EncodingType="%s">%s</Nonce>' "$B64" "$N"
    printf '<Created xmlns="%s">%s</Created>' "$WSU" "$C"
    printf '</UsernameToken></Security></s:Header>'
    printf '<s:Body>%s</s:Body></s:Envelope>' "$2"
  } > /tmp/req.xml
  curl -s -m5 -H "$CT" --data-binary @/tmp/req.xml "$1"
}

echo "== GetCapabilities ($IP:$PORT)"
B="<GetCapabilities xmlns=\"$DEV\">"
B="$B<Category>Media</Category></GetCapabilities>"
CAP=$(soap "http://$IP:$PORT/onvif/device_service" "$B")
if [ -z "$CAP" ]; then
  echo "tidak ada jawaban ONVIF di port $PORT (coba: sh $0 $IP 8000)"
  exit 1
fi
if echo "$CAP" | grep -qi 'NotAuthorized\|Fault'; then
  echo "Ditolak kamera. Potongan jawaban:"
  echo "$CAP" | grep -o '<[^>]*Text[^>]*>[^<]*' | head -3
  echo "(cek PIN, dan jam kamera vs RPi: $(date -u +%T) UTC)"
  exit 1
fi
MEDIA=$(echo "$CAP" | grep -o 'XAddr>[^<]*' | grep -i media \
        | head -1 | cut -d'>' -f2)
echo "media service: $MEDIA"
[ -z "$MEDIA" ] && { echo "$CAP" | head -c 800; echo; exit 1; }

echo "== Profil & URL RTSP"
PROF=$(soap "$MEDIA" "<GetProfiles xmlns=\"$MED\"/>")
TOKENS=$(echo "$PROF" | grep -o 'Profiles[^>]*token="[^"]*"' \
         | grep -o 'token="[^"]*"' | cut -d'"' -f2)
[ -z "$TOKENS" ] && { echo "$PROF" | head -c 800; echo; exit 1; }
for T in $TOKENS; do
  B="<GetStreamUri xmlns=\"$MED\"><StreamSetup>"
  B="$B<Stream xmlns=\"$SCH\">RTP-Unicast</Stream>"
  B="$B<Transport xmlns=\"$SCH\"><Protocol>RTSP</Protocol></Transport>"
  B="$B</StreamSetup><ProfileToken>$T</ProfileToken></GetStreamUri>"
  URI=$(soap "$MEDIA" "$B" | grep -o 'Uri>rtsp[^<]*' | cut -d'>' -f2)
  echo "  profil $T -> $URI"
done
rm -f /tmp/n /tmp/req.xml
