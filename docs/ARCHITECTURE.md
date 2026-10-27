# Architecture

This document has three parts: (1) the production deployment as it exists today, (2) how Marzban works internally, and (3) the Paydar concepts and target architecture. The facts were snapshotted from the live server on 2026-10-16, and section 1 was updated after the move to the ESX server on 2026-10-27. Re-verify anything you depend on (see `OPERATIONS.md`).

---

## 1. Production deployment (today)

### Host
- **Since 2026-10-27:** VM `Ubuntu26-VPN` on the owner's ESXi host ESX1 (Iran). Ubuntu 26.04, kernel 7.0, 8 vCPU (E5-2620 v3), 5 GB RAM, 77 GB disk.
- **Interfaces:**
  - `ens192` `79.127.32.253/29` + secondary `79.127.32.251/29` (added 2026-10-27, persisted in `/etc/netplan/00-installer-config.yaml`). Clients connect to `.251`: `mbn.myp2p.uk` points there (Cloudflare, DNS only). `.253` is not reachable from the mobile operators (MCI, Irancell), so it stays only as the primary/source address for outbound traffic and for OpenGate.
  - `ens256` `192.168.200.33/24`: internal LAN of the pfSense "lite" VMs. The WireGuard outbounds use it.
  - `ens224` `192.168.100.43`: fiber LAN, management only.
- SSH: port 4915, user `farzin` with sudo. Root login is not used.
- **Shared host:** the OpenGate VPN gateway also runs here, in docker (`opengate`, `opengate-postgres-1`). It owns policy routing: `from 79.127.32.253 lookup 201` and fwmark tables. Don't touch its rules; Marzban does not need them.
- Firewall: `ufw` is active. Only 443/tcp, 80/tcp (certbot) and the VLESS ports (rules commented `marzban vless`) are open for Marzban. Port 24000 is **not** reachable from outside.
- **Previous host (until 2026-10-27):** VPS `ubuntu-sajjad`, `185.129.119.176` (MarzbanAbalon). It is now only a DNAT bridge to the new host (iptables chain `PG_BRIDGE`) until its lease expires (~2026-10-29). Don't run Marzban, Xray or the WG outbounds there again unless you are rolling back.

### Process / port map

| Listener | Process | Purpose |
|---|---|---|
| `0.0.0.0:443` | haproxy 3.2 (systemd) | TCP/SNI router. Everything goes to the panel `127.0.0.1:24000` |
| `0.0.0.0:24000` | Marzban (uvicorn, inside docker, host network) | API, dashboard, subscription. TLS is terminated here with the `/var/lib/marzban/certs/mbn.myp2p.uk.*` certs. Blocked by ufw from outside |
| 47 VLESS ports (see below) | Xray, child process of Marzban | User traffic |
| `127.0.0.1:1` | Xray | `Information` inbound. It is a fake inbound used only to show "data left / days left" as a config entry in subscriptions |
| `:80` | certbot (only during renewal) | HTTP-01 challenge |

Not migrated from the old host, on purpose: the standalone Xray on `:2448` (unused), unbound, and the haproxy backends for `paydpan.eladmin.uk` and `shekarchi.easyinbox.info` (retired domains).

### DNS
- Marzban and Xray resolve through **Control D (unfiltered)**, `76.76.2.0` and `76.76.10.0`.
  - The container gets them via a bind-mounted `/opt/marzban/resolv.conf`.
  - Xray gets them from the `dns.servers` block in `xray_config.json`.
- Both resolvers are routed **only through `outa`**: `PostUp` in `/etc/wireguard/outa.conf` adds `/32` routes to them. Iranian resolvers return filtered answers (e.g. `10.10.34.35`), so DNS must leave the country.
- The host's own resolver is not changed, so OpenGate and the OS are unaffected.
- If `outa` is down, Marzban's DNS fails too. Check `outa` first when users report "connected, no internet".

### Marzban container
- **Container:** `/opt/marzban/docker-compose.yml` defines service `marzban`, so the container name is `marzban-marzban-1`. It uses `network_mode: host`, `restart: always`, and mounts `/var/lib/marzban` plus `/opt/marzban/resolv.conf`.
- **Image:** `paydar/marzban:abalon-20261026`, a local image committed from the running production container on 2026-10-26 (base `gozargah/marzban:latest` v0.8.4). It already contains the Paydar hot patches, so recreating the container keeps them. It exists only on this host; never `docker compose pull`.
- **Env:** `/opt/marzban/.env`; a redacted copy is at `deploy/opt-marzban/env`. Key values:
  - `DASHBOARD_PATH=/paydardashadmin/`, so the dashboard is at `https://mbn.myp2p.uk/paydardashadmin/`.
  - `XRAY_SUBSCRIPTION_PATH=pysub`, so subscriptions are at `https://mbn.myp2p.uk/pysub/<token>`.
  - `XRAY_SUBSCRIPTION_URL_PREFIX=https://mbn.myp2p.uk`.
  - `XRAY_EXECUTABLE_PATH=/var/lib/marzban/xray-core/xray` (Xray 26.1.23, newer than the image's bundled one).
  - `SQLALCHEMY_DATABASE_URL=sqlite:////var/lib/marzban/db.sqlite3` (about 18 MB).
  - `CUSTOM_TEMPLATES_DIRECTORY=/var/lib/marzban/templates/`, which holds the custom subscription page.
  - `XRAY_FALLBACKS_INBOUND_TAG=TROJAN_FALLBACK_INBOUND`, which is stale because no such inbound exists.
  - The Telegram bot is disabled and `DOCS` is off, so there is no `/docs`.
- **Xray config:** `/var/lib/marzban/xray_config.json`; a copy is at `deploy/var-lib-marzban/xray_config.json`.

### Inbound → outbound → country

**TLS migration (2026-10-18).**
- **Why:** newer Xray clients (v26.10.x+) refuse plain VLESS with *"vless without TLS or other encryption is prohibited unless the server address is a private IP or domain"*. This is a client-side check, so updating the server core does not help.
- **What changed:** every location got a parallel **TCP+TLS** inbound `VlessTls<L>`, on port = old port + 10000, with the same `mbn.myp2p.uk` cert and the same outbound. Hosts have `⚡TLS` in the remark and `sni=mbn.myp2p.uk`.
- **Order:** TLS inbounds come first in `xray_config.json`, so they appear first in subscriptions.
- **Transition:** the plain `VlessWs<L>` inbounds remain during a 2–4 week transition, then get removed.
- **Singapore:** `VlessWsO` was already TLS. It only got `⚡TLS` in its remark.
- **Exclusions:** users who had `VlessWs<L>` excluded also got `VlessTls<L>` excluded.
- **Reseller bots:** a bot that creates users with an explicit `inbounds` list must add the `VlessTls*` tags. A user created via the API *without* `inbounds` gets **no** inbounds at all (Marzban 0.8.4 quirk: the pydantic default isn't validated).


Every user-facing inbound is VLESS. All of them listen on `0.0.0.0`; their ports are in `xray_config.json` (`VlessTls*` on 12094–19143, plain `VlessWs*` on 2094–9143, `VlessWsO` on 6704). Every one is plain TCP with no security, except `VlessWsO`, which is gRPC + TLS.

> The `Ws` in the tag names is historical; none of them is WebSocket.

Routing: rule `inboundTag [VlessWsX, VlessTlsX] → outboundTag outx`, plus `geoip:private → BLOCK`. Each `outX` outbound is Xray `freedom` with `sockopt.interface = "outX"`, which binds the socket to the WireGuard interface of the same name.

| Inbound | Outbound / WG iface | Host remark (country) |
|---|---|---|
| VlessWsA | outa | Daily Fast (also an IP-based host "Daily Fast 2", now `79.127.32.251`) |
| VlessWsB | outb | Switzerland |
| VlessWsC | outc | Italy |
| VlessWsD | outd | Nigeria (+ IP host) |
| VlessWsE | oute | Australia |
| VlessWsF | outf | Canada |
| VlessWsG | outg | Georgia |
| VlessWsH | outh | Turkey |
| VlessWsI | outi | Germany |
| VlessWsJ | outj | UAE |
| VlessWsK | outk | Finland |
| VlessWsL | outl | UK |
| VlessWsM | outm | Oman |
| VlessWsN | outn | Netherlands |
| VlessWsO | outo | Singapore. This is the only TLS/gRPC inbound, and the only one reported to work on new clients |
| VlessWsP | outp | Austria |
| VlessWsQ | outq | Sweden |
| VlessWsR | outr | France |
| VlessWsS | outs | USA |
| VlessWsT | outt | Egypt |
| VlessWsU | outu | Albania |
| VlessWsV | outv | India |
| VlessWsW | outw | Japan |
| VlessWsX | outx | Bulgaria |
| — | outy | Xray outbound still exists in `xray_config.json`, but no inbound or rule uses it and there is no `outy` interface on the new host (orphan) |

The orphan hosts `VlessWsAA` and `VlessWsDirect` were deleted from the DB during the move.

### WireGuard outbounds
- The configs are `/etc/wireguard/outa.conf` … `outx.conf`. Redacted copies are in `deploy/wireguard/`. They run under enabled `wg-quick@outX` units, so they come back after a reboot.
- Each one is a client of a pfSense "lite" VM on the same ESX LAN, which then exits through a commercial VPN. Since 2026-10-27 the endpoints are the lites' **private** IPs over `ens256`:

| Tunnels | Endpoint | pfSense |
|---|---|---|
| `outa`–`outh` | `192.168.200.24:17450` | lite2 |
| `outi`–`outp` | `192.168.200.23:17455` | lite1 |
| `outq`–`outx` | `192.168.200.22:17460` | lite3 |

  The old public endpoints (`79.127.32.254:<port>`, DNAT on Mikrotik3) still work as a fallback. Backups of the public-endpoint configs are in `/root/migrate/wg-public-endpoint/` on the host.
- Every config has `Table = off`, so no default routes are installed. Traffic enters a tunnel only because Xray binds sockets to the interface (`sockopt.interface`). The one exception is the two Control D `/32` routes in `outa.conf` (see DNS above).
- **Consequence for redundancy:** a standby server must not bring these up with the same keys. The pfSense peer endpoint would flap between the two servers' IPs.

### TLS certificates
- Let's Encrypt (certbot, standalone HTTP-01 on :80) for `mbn.myp2p.uk`. `certbot.timer` renews; a deploy hook installs the cert and schedules a quiet-hour restart. See `OPERATIONS.md` → Certificates.

### Tenants
- **Admins:** one sudo admin (`paydar`) and 9 non-sudo resellers (`geo`, `blade`, `mamareza`, `alireza.premium`, `mahan`, `anypremium`, `digitalro`, `mehdi`, `mojtabamojed`).
- **Users:** about 870 in total. The largest reseller has about 450.

### Other things on the host (not part of the app)
- `/root/migrate/`: material from the 2026-10-27 move (the old host's full backup tarball, `cutover.sh` and its log, the dry-run DB, and the public-endpoint WG configs). Contains secrets.
- `/root/mahan-api/`: API guide and **token** for reseller `mahan`. Treat it as a secret.
- `/root/Marzban`: an old upstream clone copied from the old host. Don't assume it is current; this repo is the source of truth.
- There are still no automated DB backups (ROADMAP phase 1).

---

## 2. Marzban internals (what you need to change it safely)

### Startup
- `main.py` runs uvicorn on `app:app`.
- `app/__init__.py` creates the FastAPI app and an APScheduler `BackgroundScheduler`, then imports `dashboard`, `jobs`, `routers` and `telegram`. Importing them registers routes and jobs.
- `app/xray/__init__.py` loads `XRAY_JSON` into an `XRayConfig`. It also creates the `XRayCore` process wrapper and the gRPC `XRayAPI` client, and holds the `nodes` dict.
- Job `0_xray_core.py` starts Xray on startup with the config produced by `config.include_db_users()`. It also health-checks Xray every `JOB_CORE_HEALTH_CHECK_INTERVAL` (10 s) and restarts it on failure.

### Config generation (`app/xray/config.py`)
- `XRayConfig` parses the JSON. It also builds `inbounds_by_tag` and `inbounds_by_protocol`, which `GET /api/inbounds` returns and which the user forms use.
- `include_db_users()` deep-copies the config and injects every active or on-hold user's credentials into the matching inbound `clients` list. The user's `proxies` decide the protocol; `excluded_inbounds` decide which tags are skipped.
- The DB is the source of truth for users. **Never put users in `xray_config.json` by hand.**

### Live user changes (`app/xray/operations.py`)
- `add_user`, `update_user` and `remove_user` push changes to the running Xray through the gRPC API, with no restart.
- Routers call them in FastAPI `BackgroundTasks` after the DB write.
- A full Xray restart (`POST /api/core/restart`, sudo) regenerates the config from the DB.

### Background jobs (`app/jobs/`)

| Job | Interval | Does |
|---|---|---|
| `record_user_usages` | 10 s | Reads per-user traffic counters from Xray stats. Adds them to `users.used_traffic`, `admins.users_usage` (the reseller's running total) and `node_user_usages` |
| `record_node_usages` | 30 s | Adds node/system totals to `system.uplink/downlink` and `node_usages` |
| `review` (review_users) | 10 s | Marks users `limited` (over data_limit) or `expired`, and removes them from Xray. Activates `on_hold` users on first connect or timeout. Applies `next_plan` |
| `reset_user_data_usage` | 1 h | Resets traffic for users with `data_limit_reset_strategy` (day/week/month/year) |
| `remove_expired_users` | 6 h | Deletes users expired longer than `USERS_AUTODELETE_DAYS`, if that is enabled |
| `send_notifications` | 30 s | Sends webhook and Telegram notification queue |

Usage coefficients come from nodes (`usage_coefficient`). The main core's coefficient is 1.

### Data model (`app/db/models.py`)

| Table | Fields and notes |
|---|---|
| `admins` | `username`, `hashed_password`, `is_sudo`, `telegram_id`, `discord_webhook`, `users_usage` (traffic of this admin's users since the last admin usage reset), `password_reset_at` |
| `users` | `username`, `status` (active / disabled / limited / expired / on_hold), `used_traffic`, `data_limit`, `data_limit_reset_strategy`, `expire`, `on_hold_*`, `sub_revoked_at`, `sub_updated_at`, `online_at`, `note`, `admin_id` (owner), `next_plan` |
| `proxies` | Per-user protocol settings (vless id, flow, etc.). Excluded inbounds go through the `exclude_inbounds_association` table |
| `hosts` | Per-inbound "host" entries that turn into links in subscriptions: remark, address, port, sni, host, path, security override, alpn, fingerprint, mux, fragment, noise |
| `user_templates` | Templates resellers can apply |
| `nodes` | Remote nodes. Unused here |
| Usage history | `user_usage_logs`, `admin_usage_logs`, `node_usages`, `node_user_usages`, `system` |
| Notifications | `notification_reminders` |

Migrations are Alembic (`app/db/migrations/versions/`, 62 revisions). Marzban runs `alembic upgrade head` on container start.

### Auth
- `POST /api/admin/token` (OAuth2 password form) returns a JWT that is valid for `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` (1440).
- The JWT payload is `{sub: username, access: "sudo"|"admin", iat/created_at}`.
- Tokens issued before `password_reset_at` are rejected.
- The dashboard stores the token in `localStorage['token']`. The Paydar `reseller.js` decodes `access` from it.
- **Dependencies:**
  - `Admin.get_current`: any valid admin.
  - `Admin.check_sudo_admin`: sudo, otherwise 403.
  - `get_validated_user` (`app/dependencies.py`): the user exists and the caller is sudo or owns it, otherwise 403.
- `crud.get_users(..., admin=dbadmin)` scopes list endpoints for non-sudo callers.

### Subscription (`app/routers/subscription.py`, `app/subscription/`)
- `GET /pysub/{token}` → the token encodes the username plus the `created_at` of the revoke. The response depends on the client:
  - browsers get the HTML page (custom template)
  - a known `User-Agent` gets client-specific output: v2ray base64, clash YAML or sing-box JSON
- Also `/{token}/info`, `/{token}/usage` and `/{token}/{client_type}`.
- Links are built from **hosts** (`app/subscription/share.py`). Format variables in remarks/addresses include `{USERNAME}`, `{DATA_LEFT}`, `{DAYS_LEFT}`, `{EXPIRE_DATE}`, `{PROTOCOL}`, `{TRANSPORT}`, and others.

---

## 3. Paydar concepts and target architecture

### Glossary

| Term | Meaning |
|---|---|
| **Paydar** (پایدار) | The service/brand |
| **Reseller** (ریسلر) | Non-sudo Marzban admin. Creates and manages only their own users. Billed on `admins.users_usage` |
| **Outbound** | One exit path to a foreign country. Today: one WireGuard interface `outX` plus the Xray `freedom` outbound bound to it |
| **Location / Server X** | What end users see. One inbound + host remark, mapped 1:1 to an outbound |
| **Host** | Marzban `hosts` row. Controls the address, port, sni and remark in generated links |
| **Gateway Group** | (Planned) An ordered set of outbounds of any type, with health-checked failover. Implemented as one Linux routing table per group |
| **Paydar Core** | (Planned) Separate FastAPI service that owns accounts, services, resellers, billing and non-Xray protocols. Marzban becomes the Xray driver |
| **Lifeline account** (اکانت راه نجات) | (Planned) Built-in OS VPN protocols (IKEv2, L2TP, SSTP) that work without an app, for emergencies and iPhone |
| **Quiet hour** (ساعت خلوت) | Owner-designated low-traffic window when restarts are allowed |
| **Standby** | (Planned) Second Iranian server with replicated data. Promoted by switching DNS |
| **Foreign server** (سرور خارج) | (Planned) Server outside Iran that runs Telegram bots and holds offsite backups, reached through a tunnel over the outbounds |

### Target architecture (summary of ROADMAP)

```
Reseller panel / apps / extension / bots ──► Paydar Core API ──► Marzban API ──► Xray
                                                │
                                                ├─► drivers: WireGuard, OpenVPN, strongSwan (IKEv2/L2TP), accel-ppp (SSTP/PPTP), mtg (MTProto)
                                                ├─► Account → Services (one sub link, per-service protocol/outbound/limits)
                                                ├─► Resellers as a tree, with credit and pricing
                                                └─► payments, multi-tenant reseller bots
Primary (Iran) ══ DB replication ≤5 min ══► Standby (Iran, passive)
      └── tunnel via outbounds/Gateway Group ──► Foreign server: bots, Telegram API, offsite backups
```

Phase order: 1 stabilise (TLS/Reality fix, backend reseller limits, custom image, monitoring bot, backups, foreign relay), then 1.5 warm standby, 2 Core and sales, 3 single-user protocols and sub-resellers, 3.5 multi-type outbounds and gateway groups, 4 clients and branding. The details are in `docs/ROADMAP.md`.

### Design principles the owner has agreed to
- Marzban stays a thin Xray controller. New domain logic goes in Paydar Core with its own DB (PostgreSQL proposed).
- Everything client-facing uses **domains, never IPs**, so DNS failover works.
- Bots and their tokens live **only** on the foreign server.
- A standby is passive. Xray, the outbound interfaces and the accounting jobs stay off there, to avoid WG endpoint flapping and double-counting.
- Backups use `sqlite3 .backup` (consistent snapshot), are encrypted with `age`, and are stored on three locations.
