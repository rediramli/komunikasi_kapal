echo "== sourceOnDemand lines"
grep -n 'sourceOnDemand' /etc/mediamtx/mediamtx.yml
echo
echo "== dlink + dlink_sub blocks (PIN masked, source lines only)"
grep -nE '^\s*(dlink|dlink_sub):|source:|sourceOnDemand|rtspTransport' /etc/mediamtx/mediamtx.yml \
  | sed 's/admin:[^@]*@/admin:***@/'
echo
echo "== mediamtx service state"
systemctl is-active mediamtx
