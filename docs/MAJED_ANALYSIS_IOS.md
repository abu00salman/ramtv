# تحليل MajedSport 1.4.0 (phone) والاستفادة منه في RaM tv للآيفون

- الملف: `MajedSport-1.4.0-phone.apk`
- SHA-256: `f06eea9a0993a2605a765f3cc53983b308215a53266aaebe890a015f818d4f4a`
- الأدوات: JADX 1.5.1 (فك dex، مع `--show-bad-code` للدوال التي فشل فكها)، و`unzip`، و`strings`.
- **الحدود:** فحص ساكن فقط. لم يُشغَّل التطبيق ولم تُقس سرعته. أسماء Media3 الداخلية مشوّشة (R8)، فكل ما يُنسب إليها مستنتج من البنية والقيم، وليس من أسماء صريحة.
- لم يُنسخ أي كود أو أصول أو هوية أو روابط أو مفاتيح. RaM tv لا يتصل بخوادم ماجد.

## النتائج

**المصطلحات:** "مؤكد" = موجود حرفيًا في الكود. "مستنتج" = من البنية أو الأسماء المشوّشة. "يحتاج تشغيل" = لا يمكن الحكم عليه بدون تجربة.

| # | النتيجة | الدليل | الحالة |
|---|---|---|---|
| 1 | المشغل Media3 ExoPlayer 1.11.1 | النص `[AndroidXMedia3/1.11.1]` في `PlayerActivity.run()` | مؤكد |
| 2 | مفكّك FFmpeg إضافي (Nextlib) مع "decoder fallback" (افتراضيًا مفعّل) | `bx0.e`: `NextRenderersFactory`، و`decoder_fallback` و`prefer_extensions`، ومكتبات `libavcodec.so` و`libmedia3ext.so` | مؤكد |
| 3 | التخزين المؤقت: بدء التشغيل بعد 1 ثانية، وبعد التعثر 2.5 ثانية، والحد الأدنى 20 ثانية، والأقصى 60 ثانية | `bx0.e`: `bufferForPlaybackMs=1000`، `bufferForPlaybackAfterRebufferMs=2500`، `minBufferMs=20000`، `maxBufferMs=60000` | مؤكد (القيم). الأثر يحتاج تشغيل |
| 4 | مهلة الاتصال والقراءة 15 ثانية، وترويسات Referer وOrigin وCookie وUser-Agent من الإعدادات | `bx0.a`: `hwVar.o0 = 15000`، و`I1(c,"Referer"…)` | مؤكد |
| 5 | فحص نوع الرابط قبل التشغيل: GET بأول 2 KB (`Range: bytes=0-2047`) بمهلة 8 ثوانٍ، ثم Content-Type، ثم بصمة الملف | `r61.run()` (`setConnectTimeout(8000)`، `Range`)، و`bx0.b/c/d` (m3u8 وmpd وmpegurl وdash+xml) | مؤكد |
| 6 | خطأ تحليل لرابط مجهول النوع (3001–3003): إعادة واحدة كـ HLS | `u61.tmp`: `playerActivity.nul("application/x-mpegURL")` | مؤكد |
| 7 | خطأ "BEHIND_LIVE_WINDOW" (1002): رجوع للحافة الحية وإعادة التحضير | `u61.tmp`: `i == 1002` ثم إعادة الموضع و`prepare` | مؤكد (السلوك مستنتج من البنية) |
| 8 | رسائل خطأ مفصّلة: شبكة (2001/2002)، HTTP (2004/2005)، صيغة (3003/4005)، DRM (6001–6006) | `u61.tmp` و`R.string.error_*` | مؤكد |
| 9 | **لا يوجد** إعادة اتصال تلقائية لأخطاء الشبكة. تظهر رسالة خطأ فقط | لم يوجد مسار إعادة لـ 2001/2002 في `u61.tmp` | مستنتج |
| 10 | التقديم في البث الحي محدود بـ 5 ثوانٍ قبل الحافة، مع رسائل عربية | `PlayerActivity.o0` (`5000`، "يجب أن يبقى 5 ثوانٍ") | مؤكد |
| 11 | قفزات تقديم وتأخير 10 ثوانٍ | `bx0.e`: `n60.Oo = 10000`، `n60.nul = 10000` | مستنتج (أسماء مشوّشة) |
| 12 | PiP بنسبة أبعاد الفيديو الحقيقية بين 0.42 و2.39 | `PlayerActivity.Oo()` | مؤكد |
| 13 | "إيقاف مؤقت" للمشغل بين الشاشات (مشغل مصغّر أو انتقال) | `PlayerActivity.for()` يحفظ المشغل في `qi3` | مستنتج |
| 14 | لغة صوت وترجمة مفضّلة، و"tunneling"، وحد 1080p على التلفزيون | `bx0.e`: `audio_language`، `subtitle_language`، `tunnel`، `1920x1080` | مؤكد |
| 15 | مؤقت نوم: 15 و30 و45 و60 و90 دقيقة | `PlayerActivity.g = {0,15,30,45,60,90}` | مستنتج |
| 16 | أوضاع الصورة: ملاءمة، تكبير، ملء | `PlayerActivity.f` (`resize_fit/zoom/fill`) | مؤكد |
| 17 | جدول `epg_programmes` (channelId، title، start/end مع فهارس) | `p6` (Room schema) | مؤكد. **لم يُعثر على أي استعلام قراءة أو كتابة له، فهو غالبًا غير مستخدم** |
| 18 | بيانات القنوات من خادم ماجد مع Play Integrity | `security/Attestation`، `LoginActivity` | مؤكد. **لا يُستخدم في RaM tv** |
| 19 | ClearKey DRM | `bx0.a` (`{"keys":[…],"type":"temporary"}`) | مؤكد. غير منقول (خارج النطاق) |

## ما نُقل إلى RaM tv للآيفون

| من ماجد | المقابل في iOS | الملفات |
|---|---|---|
| فحص النوع بأول 2 KB (5) | `StreamProbe`: Range 0–2047 بمهلة 8 ثوانٍ، ثم Content-Type، ثم البصمة (`#EXTM3U`، و0x47 لـ TS، وEBML لـ MKV، و`ftyp` لـ MP4، و`<MPD`). TS وMKV وDASH تذهب إلى VLC مباشرة بدل انتظار مهلة AVPlayer (10 ثوانٍ) | `RaMtv/StreamProbe.swift`، `RaMtv/Player.swift` |
| رسائل خطأ مفصّلة (8) | رسالة واضحة مع زر "إعادة المحاولة": الرابط غير موجود (404/410)، رفض السيرفر (401/403)، لا اتصال | `StreamProbe.swift` (`PlaybackMessage`) |
| قيم التخزين المؤقت (3) | `preferredForwardBufferDuration` بقيمة 20 ثانية للحي و60 للأفلام. وفي VLC: `network-caching` بقيمة 1500 للحي و3000 للأفلام | `Player.swift` |
| BEHIND_LIVE_WINDOW وغياب إعادة الاتصال (7، 9) | إعادة اتصال محدودة للحي في AVPlayer: 4 محاولات (1، 2، 4، 8 ثوانٍ) عند فشل التشغيل أو تعثر يتجاوز 12 ثانية، ثم الانتقال إلى VLC. يُصفَّر العداد بعد 30 ثانية تشغيل سليم. **هنا يتفوق RaM tv على ماجد** | `Player.swift` (`AVModel.reconnect`) |
| Decoder fallback (2) | المقابل في iOS: عند "صوت بلا صورة" بعد 6 ثوانٍ من الجاهزية ينتقل البث إلى VLC (FFmpeg) | `Player.swift` (`checkPictureSoon`) |
| تحرير الموارد (1) | عند تغيير القناة: `replaceCurrentItem(nil)` لإيقاف التحميل فورًا. **لا يوجد تحميل مسبق ولا مشغلات مخفية** | `Player.swift` (`deinit`) |
| EPG (17) | دليل الآن/التالي من Xtream (`get_short_epg`) مع كاش 10 دقائق، يظهر في صف القناة (مع شريط تقدّم) وفي المشغل | `RaMtv/Epg.swift`، `Store.swift`، `Screens.swift` |
| PiP والخلفية وAirPlay (12) | موجودة أصلًا عبر `AVPlayerViewController` و`UIBackgroundModes: audio`. VLC لا يدعم PiP | بدون تغيير |
| لغة الصوت والترجمة (14) | `AVPlayerViewController` يعرض المسارات المتاحة. VLC لديه قائمتا صوت وترجمة | بدون تغيير |

## لم يُنقل، ولماذا
- **Referer/Origin/Cookie المخصّصة:** تحتاج واجهة إعدادات لكل مصدر. مرشّحة للمرحلة القادمة.
- **مؤقت النوم وحد التقديم في الحي:** AVPlayer يحدّ التقديم بنفسه. مؤقت النوم ميزة لاحقة.
- **ClearKey DRM وخادم ماجد وتسجيل الدخول:** خارج النطاق، وممنوع ربط RaM tv بها.
- **تبديل الجودة:** HLS في AVPlayer يختار الجودة تلقائيًا، ولا يوجد API رسمي لقفل جودة بعينها (يمكن فقط حدّها عبر `preferredPeakBitRate`).
