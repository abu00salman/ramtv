import Foundation

private let arabic: [String: String] = [
    "Home": "الرئيسية", "Live": "مباشر", "Library": "المكتبة", "Search": "بحث", "Settings": "الإعدادات",
    "Movies": "أفلام", "Series": "مسلسلات", "All": "الكل", "Favorites": "المفضلة",
    "Continue Watching": "متابعة المشاهدة", "Play": "تشغيل", "Add Source": "إضافة مصدر",
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

func t(_ key: String) -> String {
    let isArabic = Locale.preferredLanguages.first?.hasPrefix("ar") == true
    return isArabic ? (arabic[key] ?? key) : key
}
