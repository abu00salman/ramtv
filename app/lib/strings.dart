import 'dart:ui' as ui;

const Map<String, String> _ar = {
  'Home': 'الرئيسية',
  'Live': 'مباشر',
  'Library': 'المكتبة',
  'Search': 'بحث',
  'Settings': 'الإعدادات',
  'Movies': 'أفلام',
  'Series': 'مسلسلات',
  'All': 'الكل',
  'Favorites': 'المفضلة',
  'Continue Watching': 'متابعة المشاهدة',
  'Recent Channels': 'قنوات شاهدتها مؤخراً',
  'Play': 'تشغيل',
  'Add Source': 'إضافة مصدر',
  'Try Demo': 'تجربة العرض التجريبي',
  'Sources': 'المصادر',
  'Refresh': 'تحديث',
  'Name': 'الاسم',
  'Username': 'اسم المستخدم',
  'Password': 'كلمة المرور',
  'Save': 'حفظ',
  'Cancel': 'إلغاء',
  'Season': 'الموسم',
  'About': 'حول',
  'Demo': 'تجريبي',
  'Playlist URL': 'رابط قائمة التشغيل',
  'Server URL': 'رابط السيرفر',
  'No channels': 'لا توجد قنوات',
  'No episodes': 'لا توجد حلقات',
  'Loading': 'جارٍ التحميل',
  'Reconnecting': 'إعادة الاتصال',
  'Audio': 'الصوت',
  'Subtitles': 'الترجمة',
  'Speed': 'السرعة',
  'Aspect': 'نسبة العرض',
  'Fit': 'ملاءمة',
  'Fill': 'ملء',
  'Stretch': 'تمديد',
  'Welcome to RaM tv': 'مرحباً بك في RaM tv',
  'Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content.':
      'أضف قائمة M3U أو بيانات سيرفر خاصة بك لتبدأ المشاهدة. RaM tv مشغّل فقط ولا يتضمن أي قنوات أو محتوى.',
  'RaM tv is a player only. It does not provide or include any channels, playlists or content. Use only sources you are authorized to access.':
      'RaM tv مشغّل فقط. لا يقدّم ولا يتضمن أي قنوات أو قوائم أو محتوى. استخدم مصادر مصرّحاً لك بها فقط.',
  'Search channels, movies, series': 'ابحث في القنوات والأفلام والمسلسلات',
  'Stream unavailable. Check your connection or try another channel.':
      'البث غير متاح. تحقق من الاتصال أو جرّب قناة أخرى.',
  'Artwork': 'الصور',
  'Clear artwork cache': 'مسح ذاكرة الصور',
};

bool get isArabic => ui.PlatformDispatcher.instance.locale.languageCode == 'ar';

String t(String key) => isArabic ? (_ar[key] ?? key) : key;
