import Foundation

private let arabic: [String: String] = [
    "Fit": "ملاءمة", "Fill": "ملء", "Stretch": "تمديد", "Reconnecting": "إعادة الاتصال",
    "Stream unavailable. Check your connection or try another channel.": "البث غير متاح. تحقق من الاتصال أو جرّب قناة أخرى.",
    "Playback failed (stream not reachable or not supported)": "تعذّر تشغيل البث: غير متاح أو غير مدعوم.",
    "Pause": "إيقاف مؤقت",
    "Language": "اللغة", "System language": "لغة الجهاز",
    "Appearance": "المظهر", "Channel layout": "عرض القنوات",
    "List": "قائمة", "Grid": "بطاقات", "Close": "إغلاق",
    "Previous channel": "القناة السابقة", "Next channel": "القناة التالية",
    "Channel list": "قائمة القنوات", "Apple player": "مشغل Apple",
    "Apple player offers Picture in Picture for compatible streams.": "يوفر مشغل Apple صورة داخل صورة للبث المتوافق.",
    "Audio": "الصوت", "Subtitles": "الترجمة", "Artwork": "الصور",
    "Clear artwork cache": "مسح ذاكرة الصور", "TMDB API key (optional)": "مفتاح TMDB (اختياري)",
    "Posters and channel logos are fetched automatically. For best movie and series posters, add a free API key from themoviedb.org (Settings > API), then restart the app.": "تُحمّل الصور وشعارات القنوات تلقائيًا. لتحسين صور الأفلام والمسلسلات، أضف مفتاحًا مجانيًا من themoviedb.org ثم أعد تشغيل التطبيق.",
    "This product uses the TMDB API but is not endorsed or certified by TMDB.": "يستخدم التطبيق واجهة TMDB ولا ترعاه أو تعتمده TMDB.",
    "Home": "الرئيسية", "Live": "مباشر", "Library": "المكتبة", "Search": "بحث", "Settings": "الإعدادات",
    "Movies": "أفلام", "Series": "مسلسلات", "All": "الكل", "Favorites": "المفضلة",
    "Continue Watching": "متابعة المشاهدة", "Recent Channels": "قنوات شاهدتها مؤخراً", "Play": "تشغيل", "Add Source": "إضافة مصدر",
    "Try Demo": "تجربة العرض التجريبي", "Sources": "المصادر", "Refresh": "تحديث",
    "Name": "الاسم", "Username": "اسم المستخدم", "Password": "كلمة المرور", "Save": "حفظ",
    "Cancel": "إلغاء", "Season": "الموسم", "About": "حول", "Demo": "تجريبي",
    "Source Type": "نوع المصدر", "Playlist URL": "رابط قائمة التشغيل", "Server URL": "رابط السيرفر",
    "No channels": "لا توجد قنوات", "No episodes": "لا توجد حلقات", "Loading": "جارٍ التحميل",
    "Welcome to RaM tv": "مرحباً بك في RaM tv",
    "Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content.":
        "أضف قائمة M3U أو بيانات سيرفر خاصة بك لتبدأ المشاهدة. RaM tv مشغّل فقط ولا يتضمن أي قنوات أو محتوى.",
    "RaM tv is a player only. It does not provide or include any channels, playlists or content. Use only sources you are authorized to access.":
        "RaM tv مشغّل فقط. لا يقدّم ولا يتضمن أي قنوات أو قوائم أو محتوى. استخدم مصادر مصرّحاً لك بها فقط.",
    "Search channels, movies, series": "ابحث في القنوات والأفلام والمسلسلات"
]

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", arabic = "ar"
    var id: String { rawValue }
    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }
    var isArabic: Bool {
        self == .arabic || (self == .system && Locale.preferredLanguages.first?.hasPrefix("ar") == true)
    }
    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

func t(_ key: String) -> String {
    AppLanguage.selected.isArabic ? (arabic[key] ?? key) : key
}
