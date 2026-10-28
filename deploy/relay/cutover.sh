#!/usr/bin/env bash
# One-command relay swap, run from the owner's Mac:
#   1. sets up the new relay (asks the root password once if the key isn't installed yet)
#   2. points the SSH alias Relay1 at it
#   3. re-points Marzban's raw-IP hosts from the old relay to the new one
#
#   bash deploy/relay/cutover.sh NEW_IP [--relay-only]
#
# Afterwards, point mbn.myp2p.uk (Cloudflare, DNS only) at NEW_IP.
set -euo pipefail

NEW="${1:?usage: $0 NEW_IP [--relay-only]}"
MODE="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH_CONFIG="${SSH_CONFIG:-$HOME/Desktop/SSH-Configs/config}"
PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)

echo "### 1/3 relay setup on $NEW"
ssh "${SSH_OPTS[@]}" "root@$NEW" "PUBKEY='$(cat "$PUBKEY_FILE")' bash -s" < "$HERE/relay-setup.sh"

echo "### 2/3 SSH alias Relay1 -> $NEW"
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

if [ "$MODE" = "--relay-only" ]; then
  echo "### 3/3 skipped (--relay-only)"
  exit 0
fi

echo "### 3/3 Marzban hosts -> $NEW"
# Through the new relay: the Mac may sit on a foreign VPN that Iranian servers refuse.
ssh -J Relay1 Ubuntu26-VPN "sudo bash -s -- $NEW ${OLD:-}" < "$HERE/marzban-switch-relay.sh"

echo
echo "Now set mbn.myp2p.uk -> $NEW in Cloudflare (DNS only), then test from MCI and Irancell data."
