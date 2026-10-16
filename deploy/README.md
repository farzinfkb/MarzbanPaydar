# کانفیگ‌های سرور

نسخه‌ای از کانفیگ‌های سرور production، برای بازسازی سرور یا ساخت سرور standby.

| مسیر در ریپو | مسیر روی سرور |
|---|---|
| `opt-marzban/docker-compose.yml` | `/opt/marzban/docker-compose.yml` |
| `opt-marzban/env` | `/opt/marzban/.env` |
| `var-lib-marzban/xray_config.json` | `/var/lib/marzban/xray_config.json` |
| `var-lib-marzban/templates/subscription/index.html` | `/var/lib/marzban/templates/subscription/index.html` |
| `haproxy/haproxy.cfg` | `/etc/haproxy/haproxy.cfg` |
| `wireguard/out*.conf` | `/etc/wireguard/out*.conf` |
| `cron/root.crontab` | `crontab -l` (root) |
| `systemd/xray.service` | `/etc/systemd/system/xray.service` |

## چیزهایی که عمداً در ریپو نیستند
- `PrivateKey` و `PresharedKey` وایرگارد (به جایشان `<REDACTED>` گذاشته شده)
- `TELEGRAM_API_TOKEN` در `.env`
- دیتابیس `/var/lib/marzban/db.sqlite3`
- سرتیفیکیت‌ها و کلیدها: `/var/lib/marzban/certs`، `/etc/letsencrypt`، `/etc/ssl/private`
- توکن‌های API ریسلرها
- کانفیگ Xray مستقل (`/usr/local/etc/xray/config.json`، سرویس `xray.service` روی پورت 2448)، چون کلید Reality و UUID کلاینت دارد. فقط فایل سرویس systemd آن در `systemd/xray.service` است

این موارد فقط از طریق بکاپ رمزنگاری‌شده منتقل می‌شوند.

توضیح کامل معماری و روش اعمال تغییرات: `docs/ARCHITECTURE.md` و `docs/OPERATIONS.md`.
