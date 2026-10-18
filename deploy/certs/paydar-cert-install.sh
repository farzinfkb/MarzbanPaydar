#!/usr/bin/env bash
# certbot deploy hook: validate the renewed cert, install it for Marzban/Xray,
# and schedule a container restart at the next quiet hour (01:00 UTC = 04:30 Tehran).
# Installed as /usr/local/sbin/paydar-cert-install.sh and symlinked from
# /etc/letsencrypt/renewal-hooks/deploy/. Usage: paydar-cert-install.sh [--now|--no-restart]
set -euo pipefail
DOMAIN=mbn.myp2p.uk
LIVE=/etc/letsencrypt/live/$DOMAIN
DST=/var/lib/marzban/certs
log() { logger -t paydar-cert "$*"; echo "$*"; }

# certbot sets RENEWED_DOMAINS for deploy hooks; ignore other certificates
if [[ -n "${RENEWED_DOMAINS:-}" && " $RENEWED_DOMAINS " != *" $DOMAIN "* ]]; then exit 0; fi

crt=$LIVE/fullchain.pem key=$LIVE/privkey.pem
openssl x509 -in "$crt" -noout -checkend 86400 || { log "ERROR new cert expires within 24h, not installing"; exit 1; }
if [[ "$(openssl x509 -in "$crt" -noout -pubkey | sha256sum)" != "$(openssl pkey -in "$key" -pubout | sha256sum)" ]]; then
    log "ERROR cert and key do not match, not installing"; exit 1
fi

if cmp -s "$crt" "$DST/$DOMAIN.crt" && cmp -s "$key" "$DST/$DOMAIN.key"; then
    log "cert already installed, nothing to do"; exit 0
fi

cp -p "$DST/$DOMAIN.crt" "$DST/$DOMAIN.crt.prev"; cp -p "$DST/$DOMAIN.key" "$DST/$DOMAIN.key.prev"
install -m 644 "$crt" "$DST/$DOMAIN.crt.new"; install -m 600 "$key" "$DST/$DOMAIN.key.new"
mv -f "$DST/$DOMAIN.crt.new" "$DST/$DOMAIN.crt"; mv -f "$DST/$DOMAIN.key.new" "$DST/$DOMAIN.key"
log "installed cert, expires $(openssl x509 -in "$crt" -noout -enddate | cut -d= -f2)"

case "${1:-}" in
    --no-restart) exit 0 ;;
    --now) exec /usr/local/sbin/paydar-cert-restart.sh ;;
esac
# Xray and uvicorn only read the cert at start. The old cert is still valid for ~30 days,
# so wait for the quiet hour instead of dropping connections now.
systemctl stop paydar-cert-restart.timer 2>/dev/null || true
systemctl reset-failed paydar-cert-restart.service paydar-cert-restart.timer 2>/dev/null || true
systemd-run --unit=paydar-cert-restart --on-calendar='*-*-* 01:00:00 UTC' \
    --timer-property=Persistent=true /usr/local/sbin/paydar-cert-restart.sh
log "restart scheduled for next 01:00 UTC"
