# فحص محرك التشغيل — RaM tv (المرحلة 1، المهمة 0)

تاريخ الفحص: 8 نوفمبر 2026 — على `main` عند `4de9376` (إصدار build-63).
فحص بقراءة الكود فقط. لم يُعدَّل أي كود، ولم يُشغَّل أي بث أو يُقس أداء على جهاز.

## الخلاصة

| المنصة | الكود | محرك التشغيل | احتياطي |
|---|---|---|---|
| iOS (آيفون/آيباد) | Swift أصلي: `RaMtv/` | AVPlayer (`AVPlayerViewController`) | MobileVLCKit 3.6 (`Podfile`) |
| Android (هاتف) | Flutter: `app/` | `media_kit` (libmpv) | لا يوجد |
| Android TV | **نفس تطبيق Flutter** `app/` | `media_kit` (libmpv) | لا يوجد |
| macOS / Windows | نفس تطبيق Flutter | `media_kit` | لا يوجد |

**اختلاف مهم عن خطة المرحلة 1:** لا يوجد مجلد `android-tv/` ولا تطبيق Kotlin + Media3 في المستودع، ولا في أي فرع على GitHub. نسخة Android TV هي تطبيق Flutter نفسه، يكتشف التلفزيون عبر قناة `ramtv/device` (`app/ci/patch.py`) ويعرض واجهة الريموت. لذلك البنود المكتوبة لـ Media3 في المهام 2 و3 (`BehindLiveWindowException` و`DefaultLoadControl`) لا تنطبق على الكود الحالي، وتحتاج قرارًا قبل المهمة 2 (انظر آخر التقرير).

---

## 1. iOS — `RaMtv/`

### اختيار المحرك — `RaMtv/Player.swift` (`Engine.initial`)
- `m3u8 / mp4 / m4v / mov` ← AVPlayer.
- بث حي Xtream بامتداد `.ts` في مسار `/live/` ← AVPlayer على نسخة `.m3u8` من نفس الرابط، ويُحفظ رابط TS الأصلي احتياطيًا لـ VLC.
- بث حي بلا امتداد ← AVPlayer مع إضافة `.m3u8`، والاحتياطي الرابط الأصلي.
- كل ما عدا ذلك (MKV وAVI وغيرها) ← AVPlayer أولًا، ثم VLC إن فشل.
- `EnginePrefs` (نفس الملف) يتذكر لكل خادم (host) إذا فشل AVPlayer عليه مرات متكررة، فيبدأ مباشرة بـ VLC بعدها.
- يمكن التبديل يدويًا إلى "مشغل Apple" من زر في شريط VLC. **لا يوجد خيار محرك في الإعدادات.**

### الانتقال إلى VLC (التعامل مع الفشل في AVPlayer)
- `AVModel`: عند `AVPlayerItem.status == .failed` يُستدعى `onFail` فيُفتح VLC على الرابط الاحتياطي.
- مؤقت حماية بعد **10 ثوانٍ**: إن لم يبدأ التشغيل يُعتبر فشلًا ويُفتح VLC.
- **لا يوجد** تعامل مع الانقطاع أثناء التشغيل في AVPlayer: لا مراقبة لـ `AVPlayerItemFailedToPlayToEndTime` أو `PlaybackStalled`، ولا إعادة اتصال. AVPlayer يعيد التحميل بنفسه، فإن توقف البث نهائيًا يبقى معلقًا.
- **لا يوجد** فحص "صوت بلا صورة". هذا موجود فقط في فرع `development/iphone-2.0` غير المدموج (فحص `presentationSize` بعد 6 ثوانٍ).

### إعادة الاتصال في VLC — `VLCModel.mediaPlayerStateChanged` و`reconnect()`
- عند `.error` أو `.ended` لبث حي: إعادة محاولة حتى **6 مرات بفاصل ثابت ثانيتين**، مع رسالة "إعادة الاتصال... (n)".
- عند `.playing` يُصفَّر العداد. بعد 6 محاولات: رسالة "البث غير متاح".
- للأفلام: عند الخطأ تظهر رسالة فشل مباشرة بلا إعادة محاولة.
- **لا يوجد** اكتشاف تجمّد (بث "يعمل" بلا تقدم في الوقت).

### إعدادات الـ buffer
- AVPlayer: **لا شيء مضبوط**. لا `preferredForwardBufferDuration` ولا `automaticallyWaitsToMinimizeStalling`، فالقيم افتراضية من النظام.
- VLC: `:network-caching=1500` (1.5 ثانية) لكل شيء، حي وأفلام بنفس القيمة (`VLCModel.makeMedia`).
- لا إعداد للمستخدم لحجم التخزين المؤقت.

### تحميل المصادر — `RaMtv/Models.swift` و`RaMtv/Store.swift`
- **M3U:** `URLSession` بمهلة 90 ثانية، ثم `M3UParser.parse` في `Task.detached`. يقرأ `tvg-logo` و`group-title`، ويستنتج النوع من الرابط (`/series/`، `/movie/`، `.mp4/.mkv/.avi`)، ويجمّع القنوات بلا مجموعة حسب بادئة الاسم.
- **Xtream:** `player_api.php` بمهلة 90 ثانية. يتحقق من `auth` ثم يطلب 6 قوائم بالتوازي (فئات وبثوث الحي والأفلام والمسلسلات). روابط الحي `/live/u/p/ID.m3u8`، والأفلام بامتداد `container_extension`، والحلقات عبر `get_series_info`.
- `Store.makeRequest` يحوّل روابط الحي `.ts` في `/live/` إلى `.m3u8`.
- كاش القوائم في `Caches/items.json`، وتحديث تلقائي كل 6 ساعات.
- كلمة مرور Xtream في Keychain، مع بديل UserDefaults للنسخ المثبتة جانبيًا.

---

## 2. Android / Android TV / macOS / Windows — `app/` (Flutter)

### المحرك — `app/lib/ui/player.dart`
- `media_kit ^1.1.11` و`media_kit_video ^1.2.5` و`media_kit_libs_video ^1.0.5` (`app/pubspec.yaml`)، أي libmpv مع FFmpeg مضمّن.
- يُنشأ `Player()` **بلا `PlayerConfiguration`** وبلا أي خصائص mpv (`setProperty`).
- يُفتح البث بـ `Media(url, httpHeaders: {'User-Agent': 'RaMtv/1.0'})`.
- مشغل واحد لكل شاشة تشغيل. تغيير القناة وفتح متصفح القنوات لا يعيدان إنشاءه، والفيديو بمفتاح ثابت (`GlobalKey`).
- `PlaybackQueue` (`app/lib/playback_queue.dart`) يرتّب أوامر الفتح ويتجاهل الطلبات القديمة عند التبديل السريع.

### التعامل مع الانقطاع
- البث الحي عند `player.stream.error` ← `_scheduleReconnect()`: حتى **6 محاولات** بفواصل **1، 2، 4، 8، 16، 32 ثانية** (`reconnectDelay`)، مع رسالة "إعادة الاتصال... (n/6)". يُصفَّر العداد بعد 30 ثانية تشغيل سليم (`_trackHealth`). بعد 6 محاولات: رسالة فشل وزر إعادة.
- للأفلام: عند الخطأ تظهر رسالة فشل مباشرة بلا إعادة محاولة.
- **لا يوجد** اكتشاف تجمّد: إن بقي `buffering` صحيحًا للأبد بلا حدث `error` لا تبدأ إعادة الاتصال.
- **لا يوجد** زر "القناة السابقة" في شاشة الفشل، لكنه موجود في شريط الأدوات العادي.

### إعدادات الـ buffer
- **لا شيء مضبوط.** قيم media_kit الافتراضية (حجم buffer للـ demuxer حسب إصدار المكتبة)، ونفسها للحي والأفلام.
- لا خيار حجم تخزين مؤقت في الإعدادات.

### تحميل المصادر — `app/lib/m3u.dart`
- **M3U:** `http.get` بمهلة 120 ثانية، وفك الترميز والتحليل في Isolate (`compute`) مع `allowMalformed`.
- **Xtream:** `player_api.php` بمهلة 120 ثانية، والقوائم الست بالتوازي، والتحليل في Isolate. روابط الحي `/live/u/p/ID.m3u8`.
- إضافة مصدر من الهاتف عبر الشبكة المحلية (`app/lib/lan_add.dart`).
- الصوت والترجمة: تفضيل محفوظ لمسار الصوت (`pref.audio`) يُطبَّق عند وصول المسارات (`_applyTrackPrefs`).

---

## 3. الصيغ التي تفشل حاليًا

القائمة مبنية على الكود وعلى ما أبلغتَ عنه في هذه المحادثة، **وليس على اختبار منهجي** لأنه لم يُجرَ أي اختبار على جهاز.

| الصيغة | iOS (`main`) | Flutter (Android/TV) |
|---|---|---|
| HLS (H.264/AAC) | يعمل في AVPlayer | يعمل |
| MPEG-TS حي (رابط `.ts` مباشر) | AVPlayer لا يشغّل TS الخام. يجرّب نسخة `.m3u8` إن كانت Xtream، وإلا يبقى حتى مهلة 10 ثوانٍ ثم VLC. **بدء بطيء.** | libmpv يدعمه (لم يُقس) |
| HEVC داخل HLS/TS | **مُبلَّغ:** BeIN Sport 01 صوت بلا صورة في AVPlayer، ولا ينتقل إلى VLC لأن AVPlayer يعلن الجاهزية (الإصلاح في فرع `iphone-2.0` فقط) | libmpv يدعمه، والأداء على أجهزة arm32 غير مقيس |
| MKV | AVPlayer يفشل ثم VLC (قد يأخذ حتى 10 ثوانٍ إن لم يرسل خطأ) | libmpv يدعمه |
| AC3 / E-AC3 | AVPlayer يدعمها في HLS/MP4، لكن ليس داخل MKV. وVLC يدعمها | libmpv يدعمها |
| PiP مع VLC | **غير مدعوم** (PiP في AVPlayer فقط) | — |

---

## 4. ملاحظات تؤثر على المهام التالية

1. **المهمة 1 (محرك الآيفون):** التطبيق Swift أصلي، فالخيار حسب الخطة KSPlayer أو MobileVLCKit. MobileVLCKit موجود ومستعمل كاحتياطي. لا توجد واجهة موحدة `PlayerEngine`: المحركان نوعان منفصلان (`AVModel`/`AVPlayerScreen` و`VLCModel`/`VLCPlayerView`) يختار بينهما `Engine` في `PlayerScreen`. البناء غير الموقّع للـ IPA يعمل حاليًا في Actions (`build.sh` + XcodeGen + CocoaPods).
2. **المهمة 2 (إعادة الاتصال):** Flutter لديه منطق قريب من المطلوب (فواصل متزايدة)، لكنه 6 محاولات حتى 32 ثانية بدل 5 محاولات حتى 8 ثوانٍ، ولا يكتشف التجمّد. iOS-VLC بفاصل ثابت ثانيتين، وiOS-AVPlayer بلا إعادة اتصال.
3. **المهمة 3 (الـ buffer):** لا شيء مضبوط في أي منصة إلا VLC (1.5 ثانية). في media_kit يُضبط عبر `PlayerConfiguration(bufferSize: …)` وخصائص mpv مثل `cache-secs` و`demuxer-readahead-secs`، وليس `DefaultLoadControl`.
4. **فرع غير مدموج:** `development/iphone-2.0` فيه مهلة 20 ثانية وفحص "صوت بلا صورة" ومشاهدة متعددة ودليل البرامج. يتعارض جزئيًا مع ما دُمج من باتش iOS (مهلة 10 ثوانٍ و`EnginePrefs` الجديد)، ويجب التوفيق بينهما قبل المهمة 1 أو داخلها.

## قرار مطلوب قبل المهمة 2

الخطة تفترض نسخة Kotlin + Media3 لـ Android TV، وهي غير موجودة. الخياران:
- **أ)** الاستمرار بـ `media_kit` في تطبيق Flutter الحالي لكل منصات Android، وتنفيذ المهام 2 و3 و4 و5 عليه بما يعادل بنود Media3.
- **ب)** إنشاء تطبيق Android TV جديد بـ Kotlin + Media3 في `android-tv/`. هذا مشروع كبير مستقل، وأقترح أن يبدأ بتجربة مقارنة محدودة على نفس البثوث والأجهزة قبل اعتماده.
