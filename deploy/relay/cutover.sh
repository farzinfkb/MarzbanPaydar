#!/usr/bin/env bash
# One-command relay swap, run from the owner's Mac:
#   1. sets up the new relay (asks the root password once if the key isn't installed yet)
#   2. points the SSH alias Relay1 at it
#
#   bash deploy/relay/cutover.sh NEW_IP
#
# Every Marzban host uses the domain mbn.myp2p.uk (no raw IPs since 2026-11-03), so Marzban needs no change.
# Afterwards, point mbn.myp2p.uk (Cloudflare, DNS only) at NEW_IP.
set -euo pipefail

NEW="${1:?usage: $0 NEW_IP}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH_CONFIG="${SSH_CONFIG:-$HOME/Desktop/SSH-Configs/config}"
PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

echo "### 1/2 relay setup on $NEW"
ssh "${SSH_OPTS[@]}" "root@$NEW" "PUBKEY='$(cat "$PUBKEY_FILE")' bash -s" < "$HERE/relay-setup.sh"

echo "### 2/2 SSH alias Relay1 -> $NEW"
OLD=$(awk '/^Host Relay1$/{f=1;next} f&&/^Host /{f=0} f&&$1=="HostName"{print $2;exit}' "$SSH_CONFIG")
if [ -z "$OLD" ]; then
  echo "   no 'Host Relay1' in $SSH_CONFIG; add it by hand" >&2
elif [ "$OLD" != "$NEW" ]; then
  cp "$SSH_CONFIG" "$SSH_CONFIG.bak-relay-$(date +%Y%m%d-%H%M%S)"
  awk -v new="$NEW" '/^Host /{f=($0=="Host Relay1")} f&&$1=="HostName"{sub($2,new)} {print}' "$SSH_CONFIG" > "$SSH_CONFIG.tmp"
  cat "$SSH_CONFIG.tmp" > "$SSH_CONFIG" && rm "$SSH_CONFIG.tmp"   # keep the file (it may be a symlink target)
  echo "   $OLD -> $NEW"
fi
ssh -o BatchMode=yes Relay1 true && echo "   key login OK"

echo
echo "Now set mbn.myp2p.uk -> $NEW in Cloudflare (DNS only), then test from MCI and Irancell data."
echo "Keep the old relay${OLD:+ ($OLD)} running until clients have picked up the new DNS."
