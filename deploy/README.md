# کانفیگ‌های سرور

نسخه‌ای از کانفیگ‌های سرور production، برای بازسازی سرور یا ساخت سرور standby.

سرور production از ۲۰۲۶-۱۰-۲۷ ماشین `Ubuntu26-VPN` روی ESX1 است. آی‌پی اصلی آن `79.127.32.253` است، ولی از ۲۰۲۶-۱۰-۲۸ کاربران از راه سرور واسط `Relay1` با آی‌پی `62.60.207.137` وصل می‌شوند، چون `.253` و `.251` روی اپراتورهای همراه فیلتر شدند. endpoint تونل‌های وایرگارد، آی‌پی خصوصی pfSenseهای lite است و DNS مرزبان (Control D) فقط از `outa` رد می‌شود. جزئیات در `docs/ARCHITECTURE.md`.

| مسیر در ریپو | مسیر روی سرور |
|---|---|
| `opt-marzban/docker-compose.yml` | `/opt/marzban/docker-compose.yml` |
| `opt-marzban/env` | `/opt/marzban/.env` |
| `opt-marzban/resolv.conf` | `/opt/marzban/resolv.conf` (داخل کانتینر روی `/etc/resolv.conf` مونت می‌شود) |
| `var-lib-marzban/xray_config.json` | `/var/lib/marzban/xray_config.json` |
| `var-lib-marzban/templates/subscription/index.html` | `/var/lib/marzban/templates/subscription/index.html` |
| `haproxy/haproxy.cfg` | `/etc/haproxy/haproxy.cfg` |
| `wireguard/out*.conf` | `/etc/wireguard/out*.conf` |
| `cron/root.crontab` | `crontab -l` (root) |
| `certs/paydar-cert-*.sh` | `/usr/local/sbin/` (و لینک `paydar-cert-install.sh` در `/etc/letsencrypt/renewal-hooks/deploy/`) |

## چیزهایی که عمداً در ریپو نیستند
- `PrivateKey` و `PresharedKey` وایرگارد (به جایشان `<REDACTED>` گذاشته شده)
- `TELEGRAM_API_TOKEN` در `.env`
- دیتابیس `/var/lib/marzban/db.sqlite3`
- سرتیفیکیت‌ها و کلیدها: `/var/lib/marzban/certs`، `/etc/letsencrypt`، `/etc/ssl/private`
- توکن‌های API ریسلرها
- ایمیج `paydar/marzban:abalon-20261026` که پچ‌های Paydar داخلش است و فقط روی خود سرور وجود دارد

این موارد فقط از طریق بکاپ رمزنگاری‌شده منتقل می‌شوند.

توضیح کامل معماری و روش اعمال تغییرات: `docs/ARCHITECTURE.md` و `docs/OPERATIONS.md`.
