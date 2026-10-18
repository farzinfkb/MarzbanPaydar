# Operations runbook

All commands run as root on the production host. The app container is `marzban-marzban-1`. Read `CLAUDE.md` → "Hard rules" first, and remember: **no restarts without the owner's go-ahead.**

## Disruption levels

| Action | Effect on users |
|---|---|
| Reading files, `docker exec … cat/python` (read-only), `wg show`, `ss`, logs | None |
| `docker cp` of static dashboard files | None (takes effect on page reload) |
| Creating, modifying or deleting users through the API or dashboard | None for others. Xray is updated live over gRPC |
| `POST /api/core/restart`, or saving Core settings in the dashboard | Xray restarts, and **every connection drops** for about 1–3 s |
| `docker restart marzban-marzban-1` | API and Xray down for about 6 s, and **every connection drops** |
| `systemctl restart wg-quick@outX` | Users on that location drop |
| `systemctl reload haproxy` | Usually seamless. `restart` drops panel/sub connections |
| `docker compose up -d` after a change | **Recreates the container, which loses the Paydar patches** (see `PAYDAR_CHANGES.md`) |

## Inspect state

```bash
docker ps --filter name=marzban-marzban-1
docker logs --since 10m marzban-marzban-1 2>&1 | tail -100
ss -ltnp
wg show interfaces; wg show outa latest-handshakes
systemctl is-active haproxy xray unbound
# DB queries via the app's own models (no sqlite3 binary in the container):
docker exec marzban-marzban-1 python -c "
from app.db import GetDB, crud
from app.db.models import Admin, User
with GetDB() as db:
    for a in db.query(Admin).all(): print(a.username, a.is_sudo, a.users_usage)
"
```

- The image has no `sqlite3` CLI.
- For ad-hoc SQL, use Python's `sqlite3` module inside the container. Open the DB read-only, as `file:/var/lib/marzban/db.sqlite3?mode=ro` with `uri=True`.

## Getting a token for testing

- Reseller JWTs expire after 24 h.
- To test as any admin without knowing its password, mint a short-lived token inside the container:

```bash
T=$(docker exec marzban-marzban-1 python -c "from app.utils.jwt import create_admin_token; print(create_admin_token('mahan', is_sudo=False))" | tail -1)
curl -sk -H "Authorization: Bearer $T" https://mbn.myp2p.uk/api/system
```

- **Don't print or store** these tokens, or the one in `/root/mahan-api/token.txt`, in commits or docs.
- **Writes:** use them only for read-only checks unless the owner asked for a change.

## Deploying a code change (current hot-patch method)

1. **Commit and push** the change to the repo.
2. **Diff the live file against the repo's previous version** to make sure production has nothing unexpected:
   ```bash
   docker exec marzban-marzban-1 cat /code/app/routers/system.py | diff <(git show HEAD~1:app/routers/system.py) -
   ```
   If they differ, stop and investigate. Someone patched production directly.
3. **Copy the file in:** `docker cp app/routers/system.py marzban-marzban-1:/code/app/routers/system.py`.
4. **Restart if needed:**
   - Static dashboard files: you're done, the change applies on reload.
   - Python files: `docker restart marzban-marzban-1`, **only with the owner's go-ahead**.
5. **Wait for the API:** `curl -sk -o /dev/null -w '%{http_code}' https://mbn.myp2p.uk/api/system` returns `401` within about 10 s.
6. **Check the logs** for tracebacks.
7. **Verify behaviour** with a short-lived token, as above.
8. **Update** the "Live on prod?" column in `PAYDAR_CHANGES.md`.

**Rollback:** copy the pristine file back in from `/root/src/container-code/app/...` (an unpatched copy of the image code), or from `git show <commit>:path`, then restart.

## Changing Xray config

- **Where it lives:** `/var/lib/marzban/xray_config.json`, which you can edit in the dashboard (Core settings) or on disk.
- **Applying it:** saving it in the dashboard, or `POST /api/core/restart`, restarts Xray (connections drop).
- **Validate first:** `docker exec marzban-marzban-1 /var/lib/marzban/xray-core/xray run -test -config /var/lib/marzban/xray_config.json`.
  - Note that the DB users are injected at runtime, so the file itself has no clients.
- **Afterwards:** copy the new version to `deploy/var-lib-marzban/xray_config.json` and commit it. Keep secrets out: no Reality private keys.

### Adding a new location (current pattern)
1. Add `/etc/wireguard/outZ.conf` with `Table = off`, then `systemctl enable --now wg-quick@outZ`. Check the handshake with `wg show outZ`.
2. In `xray_config.json`:
   - add an outbound `{"tag":"outZ","protocol":"freedom","streamSettings":{"sockopt":{"interface":"outZ","tcpFastOpen":true}}}`
   - add a **TLS** inbound `VlessTlsZ`, copying an existing `VlessTls*` inbound. Plain VLESS is rejected by new clients
   - add a routing rule `inboundTag VlessTlsZ → outZ`
3. Apply it with `PUT /api/core/config` (sudo). This restarts only Xray, drops connections for about 1 s, and needs the go-ahead.
4. In the dashboard: add a **host** for `VlessTlsZ` (address `mbn.myp2p.uk`, sni `mbn.myp2p.uk`, remark `<flag> | <Country> ⚡TLS | <flag>`).
   - Existing users get new inbounds automatically, because Marzban stores exclusions rather than inclusions.
   - Reseller bots that pass explicit `inbounds` must add the new tag themselves.
5. Commit the redacted configs to `deploy/`.

## Certificates
- certbot (standalone on :80) manages `mbn.myp2p.uk`. `certbot.timer` tries twice a day and renews 30 days before expiry.
- **Deploy hook** `/etc/letsencrypt/renewal-hooks/deploy/paydar-cert-install.sh` → `/usr/local/sbin/paydar-cert-install.sh` (source in `deploy/certs/`):
  - validates the new cert: not expiring, and key matches cert
  - copies it atomically to `/var/lib/marzban/certs/` and keeps the old files as `*.prev`
  - schedules a one-shot `paydar-cert-restart` timer for the next **01:00 UTC (04:30 Tehran)** quiet hour
- **Why the restart waits:** Xray and uvicorn read the cert only at start, so a restart is required. The old cert is still valid for ~30 days, so waiting is safe.
- **`paydar-cert-restart.sh`:** restarts the container, then checks that ports 443 and 6704 serve the installed cert, and logs the result.
- **Daily check:** cron runs `paydar-cert-check.sh` at 06:30 UTC. It writes `/var/lib/paydar/cert-status` and warns if the served cert has < 14 days left.
- **Logs:** `journalctl -t paydar-cert`.
- **Manual:**
  - `paydar-cert-install.sh --now` installs and restarts immediately
  - `--no-restart` only installs
  - `systemctl list-timers paydar-cert-restart*` shows a pending restart
- **Dependency:** every user-facing TLS inbound (all `VlessTls*` and `VlessWsO`) depends on this cert.
- **History:** the old monthly cron (`certbot renew && cp && docker compose restart` on the 1st) was removed on 2026-10-18.

## Secrets: where they are (never commit)

| Secret | Location |
|---|---|
| WireGuard keys | `/etc/wireguard/out*.conf` |
| Marzban DB (password hashes, user UUIDs, sub tokens) | `/var/lib/marzban/db.sqlite3` |
| TLS keys | `/var/lib/marzban/certs/`, `/etc/letsencrypt/`, `/etc/ssl/private/` |
| Standalone Xray Reality key and client | `/usr/local/etc/xray/config.json` |
| Telegram bot token | Commented in `/opt/marzban/.env`. The owner should revoke it |
| Reseller token | `/root/mahan-api/token.txt` |
| GitHub deploy key | `/root/.ssh/marzbanpaydar_deploy` |

## Known issues / tech debt (as of 2026-10-16)

1. **Plain VLESS inbounds `VlessWs*` are being retired.** Newer clients reject them, and the TLS twins `VlessTls*` replaced them on 2026-10-18. Remove the plain inbounds and their hosts after the transition, around mid-November 2026. That removal needs an Xray restart.
2. **Reseller backend restriction is pending.** See `PAYDAR_CHANGES.md`. Today only the dashboard hides those actions.
3. **Paydar patches are hot-patched into the container** and lost on recreate. A custom image or bind-mount is pending.
4. **No automated backups.** There is only the one-off `/root/backups/*-20260808*`. The daily encrypted backup is the top phase-1 item.
5. **Firewall is off** (`ufw inactive`). Every port, including 24000 (panel without haproxy), is publicly reachable.
6. **Orphans and dead config:**
   - `outy` has no inbound, and its unit is inactive
   - hosts `VlessWsAA` and `VlessWsDirect` point to tags that don't exist
   - the haproxy backend `config → 127.0.0.1:12000` points at nothing
   - `XRAY_FALLBACKS_INBOUND_TAG` points to a nonexistent inbound
7. **Standalone `xray.service` on :2448** sits outside Marzban. It is undocumented beyond this note, so ask the owner what it's for before changing it.
8. **No test suite.** Upstream has none.
