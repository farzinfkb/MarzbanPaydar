#!/usr/bin/env bash
# Restart Marzban so Xray and the panel load the installed cert, then verify what is served.
set -uo pipefail
DOMAIN=mbn.myp2p.uk
log() { logger -t paydar-cert "$*"; echo "$*"; }
want=$(openssl x509 -in /var/lib/marzban/certs/$DOMAIN.crt -noout -fingerprint -sha256)
docker restart marzban-marzban-1 >/dev/null
for _ in $(seq 1 30); do
    sleep 2
    [[ "$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:24000/api/system)" == 401 ]] && break
done
# Check the panel (443 via haproxy) and one Xray TLS inbound
for port in 443 6704; do
    got=$(echo | timeout 10 openssl s_client -connect 127.0.0.1:$port -servername $DOMAIN 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
    if [[ "$got" == "$want" ]]; then log "port $port serves the new cert"; else log "ERROR port $port does not serve the installed cert"; fi
done
systemctl stop paydar-cert-restart.timer 2>/dev/null || true
