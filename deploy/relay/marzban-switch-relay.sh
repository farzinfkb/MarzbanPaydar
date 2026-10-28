#!/usr/bin/env bash
# Re-point every Marzban host entry that uses a raw IP at a new relay IP.
# Run as root on the production host (Ubuntu26-VPN). No restart needed: PUT /api/hosts applies live.
#
#   sudo bash marzban-switch-relay.sh NEW_IP [OLD_IP]
#
# OLD_IP defaults to the single raw IPv4 currently used by hosts (aborts if there are several).
# DRY=1 shows what would change without writing anything.
set -euo pipefail

NEW="${1:?usage: $0 NEW_IP [OLD_IP]}"
OLD="${2:-}"
DB=/var/lib/marzban/db.sqlite3
CONTAINER=marzban-marzban-1
API=https://127.0.0.1:24000/api/hosts
DIR=/root/migrate
TS=$(date +%Y%m%d-%H%M%S)
is_ip() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }

[ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
is_ip "$NEW" || { echo "NEW_IP '$NEW' is not an IPv4 address" >&2; exit 1; }
[ -z "$OLD" ] || is_ip "$OLD" || { echo "OLD_IP '$OLD' is not an IPv4 address" >&2; exit 1; }
install -d -m 700 "$DIR"

# Short-lived sudo token minted inside the container; never written to disk.
SA=$(python3 -c "import sqlite3;c=sqlite3.connect('$DB');print(c.execute('select username from admins where is_sudo=1 order by id limit 1').fetchone()[0])")
T=$(docker exec "$CONTAINER" python -c "from app.utils.jwt import create_admin_token; print(create_admin_token('$SA', is_sudo=True))" | tail -1)

PRE="$DIR/hosts-pre-$TS.json"
code=$(curl -sk -m15 -H "Authorization: Bearer $T" "$API" -o "$PRE" -w '%{http_code}')
chmod 600 "$PRE"
[ "$code" = 200 ] || { echo "GET hosts failed: HTTP $code" >&2; exit 1; }

PUT="$DIR/hosts-put-$TS.json"
OLD=$(python3 - "$PRE" "$PUT" "$NEW" "$OLD" <<'P'
import json, re, sys
pre, put, new, old = sys.argv[1:5]
h = json.load(open(pre))
ip = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$')
# Public IPs only: some hosts intentionally use loopback/private addresses.
private = re.compile(r'^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
used = sorted({a for l in h.values() for x in l
               if ip.match(a := x.get('address') or '') and not private.match(a)})
if not old:
    if len(used) != 1:
        sys.exit(f"cannot guess OLD_IP, raw IPs in use: {used}; pass it explicitly")
    old = used[0]
if old == new:
    sys.exit(f"hosts already use {new}, nothing to do")
out = {}
for tag, l in h.items():
    if any(x.get('address') == old for x in l):
        for x in l:
            if x.get('address') == old:
                x['address'] = new
                print(f"  {tag}: {x['remark']}", file=sys.stderr)
        out[tag] = l
if not out:
    sys.exit(f"no host uses {old}")
json.dump(out, open(put, 'w'))
print(old)
P
)
echo "== $OLD -> $NEW"

if [ "${DRY:-0}" = 1 ]; then
  echo "DRY=1: nothing written (backup of current hosts: $PRE)"
  exit 0
fi

sqlite3 "$DB" ".backup $DIR/db-pre-relay-$TS.sqlite3" 2>/dev/null \
  || python3 -c "import sqlite3;sqlite3.connect('$DB').backup(sqlite3.connect('$DIR/db-pre-relay-$TS.sqlite3'))"
chmod 600 "$DIR/db-pre-relay-$TS.sqlite3"

POST="$DIR/hosts-post-$TS.json"
code=$(curl -sk -m20 -X PUT -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  --data @"$PUT" "$API" -o "$POST" -w '%{http_code}')
chmod 600 "$POST"
[ "$code" = 200 ] || { echo "PUT hosts failed: HTTP $code (DB backup: $DIR/db-pre-relay-$TS.sqlite3)" >&2; exit 1; }

python3 - "$PRE" "$POST" "$OLD" "$NEW" <<'P'
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
old, new = sys.argv[3:5]
strip = lambda l: [{k: v for k, v in x.items() if k not in ('address', 'id')} for x in l]
bad = [t for t in a if strip(a[t]) != strip(b.get(t, []))]
addrs = [x['address'] for l in b.values() for x in l]
print(f"== done: {addrs.count(new)} hosts on {new}, {addrs.count(old)} left on {old}, tags {len(a)}->{len(b)}")
if bad: print("WARNING: other fields changed in", bad)
P
echo "   backups: $PRE  $DIR/db-pre-relay-$TS.sqlite3"
