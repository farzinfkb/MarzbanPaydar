# Paydar changes vs upstream Marzban

- **Base:** Gozargah/Marzban `v0.8.4`, commit `7f396db`. The production image `gozargah/marzban:latest` was built 2025-01-09 and is the same version.
- **Diff:** `git diff 7f396db HEAD -- app config.py` shows every code change.
- **Maintenance:** keep this file up to date with every change to Marzban code.

## Code changes

| # | Commit | Files | What | Live on prod? |
|---|---|---|---|---|
| 1 | `d8c9448` | `app/dashboard/{public,build}/statics/reseller.js`, `reseller.css`, `app/dashboard/index.html`, `app/dashboard/build/index.html` | Dashboard patch for non-sudo admins. Hides **Delete** and **Reset Usage** buttons and the **Periodic usage reset** (`data_limit_reset_strategy`) field. The role comes from the JWT `access` claim in `localStorage['token']`, and a `MutationObserver` re-applies it on every DOM change | Yes (docker cp) |
| 2 | `89e1b55` | `reseller.js` (both copies) | Also hides the **Memory usage** statistics card for resellers. It is matched by the card title text in en/fa/ru/zh | Yes (docker cp) |
| 3 | `89e1b55` | `app/routers/system.py` | `GET /api/system` for non-sudo admins: `incoming_bandwidth = admins.users_usage` (own users' traffic), `outgoing_bandwidth = 0`; memory, CPU and realtime speed are 0; `online_users` counts only own users | Yes (docker cp + restart 2026-10-13) |
| 4 | `89e1b55` | `app/db/crud.py` | `count_online_users()` takes an optional `admin` filter | Yes (as above) |

Non-code additions (no effect on runtime): `CLAUDE.md`, `docs/`, `deploy/`.

### Notes on the dashboard patch
- **Why it is not a source change:** it is a standalone script rather than a React source change, because production serves the image's prebuilt bundle. Rebuilding the bundle needs the custom image (ROADMAP phase 1).
- **On production:** `/code/app/dashboard/build/index.html` was edited in place to add the `<link>`/`<script>` tags. `404.html` was not, which is fine because the dashboard uses a hash router.
- **Fragility:**
  - **Trash icon:** the Delete button is matched by the start of the trash SVG path (`M14.74 9l-.346 9`).
  - **Text matches:** Reset Usage is matched by its button text, and the Memory card by its title text.
  - **Upgrades:** if upstream changes icons or translations, re-check these matches.
- **Security:** it is cosmetic only. The API still allows these actions, so the backend restriction below is the real fix.

## Reseller permission matrix (production today)

"Reseller" means a non-sudo admin. "Own" means users whose `admin_id` is the caller.

| Endpoint | Sudo | Reseller | Notes |
|---|---|---|---|
| `POST /api/admin/token` | ✓ | ✓ | |
| `GET /api/admin` | ✓ | ✓ self | Includes `users_usage` |
| Admin management (`/admin*`, `/admins`, admin usage, disable/activate an admin's users) | ✓ | 403 | |
| `GET /api/system` | full | **scoped** (Paydar #3) | |
| `GET /api/inbounds` | ✓ | ✓ | |
| `GET/PUT /api/hosts`, `/core/config`, `/core/restart`, `/node*` | ✓ | 403 | |
| `GET /api/core` | ✓ | ✓ | Version/started only |
| `GET /api/users`, `/users/usage` | all | own | |
| `POST /api/user` | ✓ | ✓ | Owner is set to the caller |
| `GET/PUT /api/user/{u}`, `/usage`, `/revoke_sub` | ✓ | own | |
| `DELETE /api/user/{u}` | ✓ | own ⚠ | **Should be sudo-only** (pending) |
| `POST /api/user/{u}/reset` | ✓ | own ⚠ | **Should be sudo-only** (pending) |
| `POST /api/user/{u}/active-next` | ✓ | own ⚠ | **Should be sudo-only** (pending) |
| `GET /api/users/expired` | ✓ | own | |
| `DELETE /api/users/expired` | ✓ | own ⚠ | **Should be sudo-only** (pending) |
| `POST /api/users/reset`, `PUT /user/{u}/set-owner` | ✓ | 403 | |
| `data_limit_reset_strategy`, `next_plan` in user create/modify body | ✓ | allowed ⚠ | **Should be rejected for resellers** (pending) |
| `GET /api/user_template*` | ✓ | ✓ | Create/update/delete are sudo-only |

### Pending: backend reseller restriction (ROADMAP phase 1)
- **Approved approach:**
  - Swap `Admin.get_current` / `get_validated_user` for an extra `Admin.check_sudo_admin` dependency on the four ⚠ routes.
  - In `add_user`/`modify_user`, return 403 when a non-sudo caller sets `data_limit_reset_strategy` (other than `no_reset`) or `next_plan`.
- **Deployment:** it needs a container restart, so it happens **only at a quiet hour the owner announces**.
- **Reseller bots:** these must not rely on the four endpoints. The reseller API guide (`/root/mahan-api/README-mahan.md`) doesn't list them as supported.

## Re-applying patches to a fresh container

Recreating the container (`docker compose up` with a changed compose/env, `pull`, or a new image) discards the patches. Re-apply them with:

```bash
cd /root/src/MarzbanPaydar
C=marzban-marzban-1
docker cp app/routers/system.py $C:/code/app/routers/system.py
docker cp app/db/crud.py        $C:/code/app/db/crud.py
docker cp app/dashboard/build/statics/reseller.js  $C:/code/app/dashboard/build/statics/reseller.js
docker cp app/dashboard/build/statics/reseller.css $C:/code/app/dashboard/build/statics/reseller.css
# index.html: inject the two tags into the image's own index.html (do NOT copy the repo's build/index.html, its hashed asset names differ)
docker exec $C sed -i 's#</head>#<link rel="stylesheet" href="/statics/reseller.css"><script src="/statics/reseller.js"></script></head>#' /code/app/dashboard/build/index.html
docker restart $C   # only at a quiet hour
```

- **Upstream versions:** this only works while the image is still v0.8.4.
- **New upstream version:** first diff each patched file against the new image's copy before copying anything.
- **Better fix:** a custom image (`Dockerfile` in this repo) makes all of this unnecessary.

## Merging guidance (for another project borrowing from this)
- **Changes #1 and #2** are self-contained static files that work on any Marzban 0.8.x dashboard.
- **Changes #3 and #4** are small, local patches to `system.py` and `crud.py`. They apply cleanly to 0.8.x.
- **Configs:** the production configs in `deploy/` illustrate the "one inbound → one WireGuard interface" pattern (`sockopt.interface`, `Table = off`). They are not Marzban code.
