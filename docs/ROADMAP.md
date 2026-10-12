# نقشه‌ی راه Paydar

## معماری کلی

```
پنل ریسلر / اپ‌ها / اکستنشن / ربات‌ها ──► Paydar Core API ──► Marzban API ──► Xray
                                             │
                                             ├─► درایورها: WireGuard، OpenVPN، IKEv2/L2TP/IPsec، SSTP/PPTP، MTProto، HTTPS Proxy
                                             ├─► اشتراک، حجم، انقضا، لینک ساب
                                             ├─► ریسلرها (درختی)، اعتبار، قیمت‌گذاری
                                             └─► پرداخت و ربات‌های چندمستاجره
ربات مانیتورینگ ──► سرورها، outboundها، کانفیگ‌ها، probe داخل ایران
```

- **Paydar Core** سرویس جدا (FastAPI و دیتابیس خودش) و مرجع اصلی داده‌هاست.
- **مرزبان** فقط کنترل‌کننده‌ی Xray است و فورک آن حداقلی می‌ماند.

## مدل داده‌ی پایه

- **Account** (مشتری): یک لینک ساب، یک لاگین اپ، و تعدادی Service.
- **Service**:
  - `protocol`: یکی از vless، wireguard، openvpn، ikev2، l2tp، sstp، pptp، mtproto یا https-proxy.
  - `outbound`: برای پروتکل‌های تک‌کاربره اجباری است، مثل `outa` تا `outx`.
  - `data_limit`، `expire`، `max_sessions` (تک یا چندکاربره)، `status`.
  - `credentials`: کلید WireGuard، یوزرنیم و رمز، secret، و مانند این‌ها.
- **Reseller**: `parent_id` (ساختار درختی)، اعتبار و سهمیه، قیمت‌ها، تنظیمات ربات و پرداخت.
- **Outbound**: لیست خروجی‌ها، وضعیت سلامت، و ظرفیت.

## لینک ساب

- کلاینت‌های v2ray لینک‌های VLESS را می‌گیرند.
- صفحه‌ی ساب همه‌ی سرویس‌ها را نشان می‌دهد:
  - فایل `.conf` و QR برای WireGuard
  - فایل `.ovpn`
  - یوزرنیم و رمز و سرور برای IKEv2، L2TP و SSTP
  - لینک `tg://proxy` برای MTProto
- اپ اختصاصی از نسخه‌ی JSON همین ساب از API می‌خواند.

## فازها

### فاز ۱ — تثبیت
- [ ] رفع کار نکردن کانفیگ‌ها روی کلاینت‌های جدید با TLS یا Reality (با اپ و sing-box سازگار باشد)
- [ ] محدودیت بک‌اند ریسلرها: delete، reset، active-next، data_limit_reset_strategy، next_plan
- [ ] ساخت ایمیج اختصاصی از فورک
- [ ] ربات مانیتورینگ: سرور، Xray، handshakeهای WireGuard، سرتیفیکیت‌ها، تست هر لوکیشن، probe داخل ایران
- [ ] پاک‌سازی: firewall، سرتیفیکیت‌های منقضی، `outy`، hostهای یتیم، بکاپ دیتابیس

### فاز ۲ — هسته و فروش
- [ ] Paydar Core: Account، Service، Outbound، Reseller، API و لینک ساب یکپارچه
- [ ] تست میدانی IKEv2 و L2TP روی اپراتورهای ایران
- [ ] IKEv2، L2TP و Cisco IPsec (strongSwan)، SSTP و PPTP (accel-ppp)، با RADIUS متصل به Core و «اکانت راه نجات»
- [ ] ربات فروش: کارت‌به‌کارت با تأیید رسید، رمزارز، تمدید، یادآوری

### فاز ۳ — پروتکل‌های تک‌کاربره و ریسلری
- [ ] WireGuard: یک اینترفیس برای هر outbound، peer برای هر سرویس، شمارش حجم با `wg show`، قطع خودکار
- [ ] MTProto
- [ ] OpenVPN با یوزر و رمز، تک یا چندکاربره، به ازای هر outbound
- [ ] زیرمجموعه‌گیری ریسلرها: ساختار درختی، تخصیص اعتبار از والد به فرزند، دیدن زیرمجموعه‌ها
- [ ] ربات آماده برای هر ریسلر: ریسلر توکن BotFather و شماره کارت را در پنل وارد می‌کند، یک کدبیس چندمستاجره دارد، و فروش از اعتبار خود ریسلر کم می‌شود

### فاز ۳.۵ — Outboundهای چندنوعی و Gateway Group
- [ ] هر outbound روی سرور به شکل یک اینترفیس کرنلی درمی‌آید:
  - WireGuard: اینترفیس `wg` (همین الان موجود است)
  - OpenVPN: کلاینت `openvpn` روی `tun`
  - IKEv2: strongSwan روی XFRM interface
  - V2Ray (لینک vless/vmess/trojan/ss): کلاینت sing-box در حالت TUN
  - SSH: `ssh -w` (tun) یا `-D` به‌علاوه‌ی tun2socks
- [ ] Gateway Group: یک جدول routing برای هر گروه، که Xray (با `sockopt.mark`) و کاربرهای WireGuard، OpenVPN و L2TP (با `ip rule`) هر دو از آن استفاده می‌کنند
- [ ] Health checker: تست دوره‌ای از هر عضو، آستانه‌ی خطا و hysteresis، failover و failback بر اساس اولویت، و هشدار به ربات مانیتورینگ
- [ ] NAT/MASQUERADE روی هر عضو، MSS clamping برای MTUهای متفاوت، و جلوگیری از نشت DNS
- [ ] صفحه‌ی Outbounds و Gateway Groups در پنل، با import لینک یا فایل `.ovpn` یا `.conf`
- [ ] مهاجرت `outa` تا `outx` فعلی به گروه‌ها (در ساعت خلوت)

### فاز ۴ — کلاینت‌ها و برند
- [ ] اکستنشن مرورگر و gateway پروکسی HTTPS
- [ ] اپ Flutter با sing-box: اندروید و Android TV، بعد ویندوز، بعد لینوکس و مک. آپدیت خودکار داخل اپ دارد و APK همیشه با یک کلید ثابت امضا می‌شود
- [ ] برندینگ پنل ریسلر و صفحه‌ی ساب

## تصمیم‌های باز
- حجم برای هر سرویس جداست، یا یک حجم مشترک برای کل اکانت؟
- پنل ریسلر همان داشبورد مرزبان با برند جدید باشد، یا پنل جدید روی Core؟
- قیمت‌گذاری ریسلرها و نحوه‌ی تسویه‌ی اعتبار والد و فرزند
- آیا L2TP و IKEv2 روی سرور یا IP جدا اجرا شوند؟
