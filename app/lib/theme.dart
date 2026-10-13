import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'strings.dart' as strings;

enum AppThemeMode { night, day, auto }

enum AppAccent { blue, purple, teal }

/// Every color the UI uses. Resolved from the saved theme mode + accent.
class Palette {
  final bool dark;
  final Color accent;
  final Color onAccent;
  final Color bg;
  final Color panel;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color focus;

  const Palette({
    required this.dark,
    required this.accent,
    required this.onAccent,
    required this.bg,
    required this.panel,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.focus,
  });

  static Color accentFor(AppAccent a, bool dark) {
    switch (a) {
      case AppAccent.blue:
        return dark ? const Color(0xFF2D6BFF) : const Color(0xFF0047D1);
      case AppAccent.purple:
        return dark ? const Color(0xFF8B5CF6) : const Color(0xFF6D28D9);
      case AppAccent.teal:
        return dark ? const Color(0xFF14B8A6) : const Color(0xFF0F766E);
    }
  }

  factory Palette.night(AppAccent a) => Palette(
        dark: true,
        accent: accentFor(a, true),
        onAccent: a == AppAccent.teal ? const Color(0xFF04201E) : Colors.white,
        bg: const Color(0xFF070B14),
        panel: const Color(0xFF0A1020),
        surface: const Color(0xFF121A30),
        border: const Color(0xFF1E2A48),
        text: Colors.white,
        muted: const Color(0xFFB4BDD0),
        focus: Colors.white,
      );

  factory Palette.day(AppAccent a) => Palette(
        dark: false,
        accent: accentFor(a, false),
        onAccent: Colors.white,
        bg: const Color(0xFFF3F5FA),
        panel: Colors.white,
        surface: const Color(0xFFE6EAF3),
        border: const Color(0xFFCBD3E4),
        text: const Color(0xFF0B1224),
        muted: const Color(0xFF475069),
        focus: const Color(0xFF0B1224),
      );
}

class Pal {
  /// Always the palette that was resolved for the current frame.
  static Palette current = Palette.night(AppAccent.blue);

  /// Registers a dependency on [Theme] so widgets rebuild when the theme changes.
  static Palette of(BuildContext context) {
    Theme.of(context);
    return current;
  }
}

class ThemeController extends ChangeNotifier {
  AppThemeMode mode = AppThemeMode.night;
  AppAccent accent = AppAccent.blue;
  bool simple = false;
  String? lang; // null = follow device
  SharedPreferences? _prefs;

  void load(SharedPreferences p) {
    _prefs = p;
    mode = AppThemeMode.values.firstWhere((e) => e.name == p.getString('theme.mode'),
        orElse: () => AppThemeMode.night);
    accent = AppAccent.values.firstWhere((e) => e.name == p.getString('theme.accent'),
        orElse: () => AppAccent.blue);
    simple = p.getBool('ui.simple') ?? false;
    lang = p.getString('ui.lang');
    strings.languageOverride = lang;
  }

  Palette resolve(Brightness platform) {
    final dark = mode == AppThemeMode.night ||
        (mode == AppThemeMode.auto && platform == Brightness.dark);
    return dark ? Palette.night(accent) : Palette.day(accent);
  }

  Future<void> setMode(AppThemeMode m) async {
    mode = m;
    notifyListeners();
    await _prefs?.setString('theme.mode', m.name);
  }

  Future<void> setAccent(AppAccent a) async {
    accent = a;
    notifyListeners();
    await _prefs?.setString('theme.accent', a.name);
  }

  Future<void> setLang(String? v) async {
    lang = v;
    strings.languageOverride = v;
    notifyListeners();
    if (v == null) {
      await _prefs?.remove('ui.lang');
    } else {
      await _prefs?.setString('ui.lang', v);
    }
  }

  Future<void> resetAll() async {
    mode = AppThemeMode.night;
    accent = AppAccent.blue;
    simple = false;
    lang = null;
    strings.languageOverride = null;
    notifyListeners();
    for (final k in ['theme.mode', 'theme.accent', 'ui.simple', 'ui.lang', 'pref.aspect', 'pref.audio', 'pref.sub']) {
      await _prefs?.remove(k);
    }
  }

  Future<void> setSimple(bool v) async {
    simple = v;
    notifyListeners();
    await _prefs?.setBool('ui.simple', v);
  }
}

final ThemeController themeController = ThemeController();

ThemeData buildTheme(Palette p) {
  final base = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'PlexArabic',
    brightness: p.dark ? Brightness.dark : Brightness.light,
    colorScheme: base.copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      surface: p.panel,
      onSurface: p.text,
      surfaceContainerHighest: p.surface,
      outline: p.border,
    ),
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.panel,
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.panel),
    listTileTheme: ListTileThemeData(
      textColor: p.text,
      iconColor: p.muted,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accent,
      labelStyle: TextStyle(color: p.text),
      secondaryLabelStyle: TextStyle(color: p.onAccent),
      side: BorderSide(color: p.border),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface,
      contentTextStyle: TextStyle(color: p.text, fontSize: 16),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

extension PaletteContext on BuildContext {
  Palette get pal => Pal.of(this);
}

/// 1.0 at 540dp screen height; keeps layouts proportional on any TV density.
double uiScale(BuildContext c) =>
    (MediaQuery.of(c).size.height / 540).clamp(0.85, 2.2).toDouble();

/// Explicit sizes already follow [uiScale]; only the simple-mode boost is applied on top.
TextScaler uiTextScaler() => TextScaler.linear(themeController.simple ? 1.2 : 1.0);
