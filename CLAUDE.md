# CLAUDE.md — MarzbanPaydar

Start here. This file is the entry point for any agent (Claude or otherwise) working on, merging, or borrowing from this repository.

## What this is

**MarzbanPaydar** is a private fork of [Gozargah/Marzban](https://github.com/Gozargah/Marzban) **v0.8.4** (upstream commit `7f396db`). It runs a commercial VPN service called **Paydar** for users in Iran.

- **Marzban** is a FastAPI + SQLAlchemy panel that manages an Xray-core process. It handles users, quotas, expiry, subscription links, and a React admin dashboard.
- **Paydar's model:**
  - Iranian clients connect to one server in Iran over VLESS.
  - Each inbound is routed out through a different WireGuard tunnel, called an "outbound" (`outa` … `outx`). Each tunnel lands in a different country.
  - Resellers are non-sudo Marzban admins who sell accounts to end users.
- The long-term plan is a separate **Paydar Core** service, with Marzban reduced to an Xray controller. Read `docs/ROADMAP.md`, which is written in Persian.

The fork is intentionally **thin**. Paydar changes to Marzban code are kept small, isolated, and listed in `docs/PAYDAR_CHANGES.md`. New big features belong in a separate service (Paydar Core), not in this codebase.

## Document map

| File | Read it when |
|---|---|
| `docs/ARCHITECTURE.md` | You need the production topology, the request/traffic flow, Marzban internals, or the data model |
| `docs/PAYDAR_CHANGES.md` | You are merging, rebasing on upstream, or need to know what differs from stock Marzban |
| `docs/OPERATIONS.md` | You will touch the live server: deploy, restart, verify, logs, certs, outbounds, known issues |
| `docs/ROADMAP.md` | You are planning features (Persian). It has the phases, the target data model, and open decisions |
| `deploy/README.md` | You need the repo path ↔ server path map for production configs |
| `README.md` etc. | Upstream Marzban docs. They are still accurate for Marzban behaviour |

## Repository layout

```
app/                 Marzban application (FastAPI)
  routers/           HTTP API: admin, user, system, core, node, user_template, subscription, home
  models/            Pydantic request/response models (Admin auth helpers live in models/admin.py)
  db/                SQLAlchemy models (models.py), all queries (crud.py), Alembic migrations
  xray/              Xray config generation (config.py), process control (core.py), live user ops via gRPC (operations.py), nodes
  jobs/              APScheduler jobs: usage recording, user review (expire/limit), resets, notifications
  subscription/      Subscription renderers: v2ray, clash, sing-box, outline
  dashboard/         React + Chakra UI admin panel (src/), prebuilt bundle (build/), Paydar patch in public/statics/reseller.*
  telegram/ discord/ Built-in notification/admin bots (Telegram bot is disabled in production)
  templates/         Default Jinja templates (production overrides them in /var/lib/marzban/templates)
config.py            All settings, read from env/.env (python-decouple)
xray_api/            Generated gRPC client for the Xray API
cli/                 marzban-cli (typer)
deploy/              Production server configs, secrets redacted (Paydar-only)
docs/                Paydar docs (Paydar-only)
```

## Hard rules

1. **Never commit secrets.** That covers:
   - WireGuard `PrivateKey`/`PresharedKey`, the Xray Reality private key, and client UUIDs
   - the SQLite DB and certificates/keys
   - Telegram bot tokens, and reseller JWTs or passwords (`/root/mahan-api/token.txt`)

   Replace them with `<REDACTED>`. Before every commit, grep the diff for `PrivateKey`, `token`, `password`, `BEGIN .*PRIVATE`, and long base64 strings.
2. **Production is live with ~870 paying users.**
   - **Restarting the Marzban container** drops every connection for a few seconds. Do it only when the owner explicitly says so, or says it is a quiet hour ("ساعت خلوت").
   - **WireGuard interfaces and haproxy** fall under the same rule.
   - Read-only inspection is always fine.
3. **Ask before implementing features.** For any non-trivial feature the owner expects difficulty, challenges and options first, and implementation only after they say go.
4. **Commit and push after every change** to `origin` (`git@github-marzbanpaydar:farzinfkb/MarzbanPaydar.git`, branch `master`, SSH deploy key `/root/.ssh/marzbanpaydar_deploy` via the `github-marzbanpaydar` host alias).
   - Author: `farzinfkb <paydarclfkb1@outlook.com>`.
   - End messages with a `Co-Authored-By:` trailer naming the agent.
   - GitHub DNS sometimes fails transiently, so retry the push.
5. **Keep the fork thin.**
   - Prefer additive, clearly marked changes.
   - Avoid reformatting upstream files, which makes upstream merges painful.
   - Record every Marzban code change in `docs/PAYDAR_CHANGES.md`.
6. **The owner communicates in Persian.** Reply in Persian. Code, commits and these agent docs are in English; `ROADMAP.md` and `deploy/README.md` are Persian.

## How code reaches production (important)

Production runs the **stock image `gozargah/marzban:latest`** (built 2025-01-09, v0.8.4), *not* an image built from this repo.

- **How Paydar changes go live today:** the changed files are copied into the running container (`docker cp`), followed by `docker restart` when they are Python files.
- **They survive** `docker restart`.
- **They are lost** if the container is recreated (`docker compose up` after a compose/env change, `docker compose pull`, or image update).
- **Before recreating the container**, re-apply every file in the list in `docs/PAYDAR_CHANGES.md`.
- **Planned fix:** a custom image or bind-mounts (ROADMAP phase 1).

See `docs/OPERATIONS.md` → "Deploying a code change" for the exact procedure, including the pre-copy diff check.

## Dev notes

- Python 3.12 on the server image. There is no test suite in upstream Marzban. Verify with `python3 -m py_compile`, then against the live API with a short-lived token (see OPERATIONS).
- **Dashboard:** `app/dashboard/build/` is a committed prebuilt bundle.
  - Its hashed filenames differ from the bundle inside the production image, so never copy `build/index.html` or the hashed JS over production.
  - Paydar dashboard customisations are standalone files (`statics/reseller.js`, `statics/reseller.css`), loaded by a `<script>`/`<link>` added to `index.html`.
  - Keep them in **both** `public/statics/` (source) and `build/statics/` (deployed). The two copies must stay identical.
- **DB schema changes** need an Alembic migration in `app/db/migrations/versions/`. Avoid schema changes in the fork if possible; put new data in Paydar Core instead.
- **Permissions:**
  - `Admin.get_current` means any admin; `Admin.check_sudo_admin` means sudo only.
  - Owner scoping for users is done by `get_validated_user` in `app/dependencies.py`.
  - See the permission matrix in `docs/PAYDAR_CHANGES.md`.
