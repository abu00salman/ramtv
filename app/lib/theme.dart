import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'strings.dart' as strings;

enum AppThemeMode { night, black, glass, day, auto }

enum AppAccent { blue, purple, teal, orange, red, green, pink, gold, cyan, indigo }

/// Every color the UI uses. Resolved from the saved theme mode + accent.
class Palette {
  final bool dark;
  final bool glass;
  final Color accent;
  final Color onAccent;
  final Color bg;
  final Color base; // opaque color used for scrims/fades and contrast checks
  final Color panelSolid; // opaque panel color for dialogs and menus
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
    required this.base,
    required this.panelSolid,
    this.glass = false,
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
      case AppAccent.orange:
        return dark ? const Color(0xFFFF8A3D) : const Color(0xFFC2410C);
      case AppAccent.red:
        return dark ? const Color(0xFFEF4444) : const Color(0xFFB91C1C);
      case AppAccent.green:
        return dark ? const Color(0xFF22C55E) : const Color(0xFF15803D);
      case AppAccent.pink:
        return dark ? const Color(0xFFEC4899) : const Color(0xFFBE185D);
      case AppAccent.gold:
        return dark ? const Color(0xFFF5B301) : const Color(0xFF8A6100);
      case AppAccent.cyan:
        return dark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490);
      case AppAccent.indigo:
        return dark ? const Color(0xFF6366F1) : const Color(0xFF4338CA);
    }
  }

  /// White or near-black text, whichever contrasts more with the accent (always at least 4.5:1).
  static Color onAccentFor(Color c) {
    final l = c.computeLuminance();
    final white = 1.05 / (l + 0.05);
    final dark = (l + 0.05) / 0.05;
    return white >= dark ? Colors.white : const Color(0xFF0B0B0B);
  }

  factory Palette.night(AppAccent a) => Palette(
        dark: true,
        accent: accentFor(a, true),
        onAccent: onAccentFor(accentFor(a, true)),
        bg: const Color(0xFF070B14),
        base: const Color(0xFF070B14),
        panelSolid: const Color(0xFF0A1020),
        panel: const Color(0xFF0A1020),
        surface: const Color(0xFF121A30),
        border: const Color(0xFF1E2A48),
        text: Colors.white,
        muted: const Color(0xFFB4BDD0),
        focus: Colors.white,
      );

  /// Pure black (OLED friendly).
  factory Palette.black(AppAccent a) => Palette(
        dark: true,
        accent: accentFor(a, true),
        onAccent: onAccentFor(accentFor(a, true)),
        bg: const Color(0xFF000000),
        base: const Color(0xFF000000),
        panelSolid: const Color(0xFF0B0B0B),
        panel: const Color(0xFF0B0B0B),
        surface: const Color(0xFF161616),
        border: const Color(0xFF2B2B2B),
        text: Colors.white,
        muted: const Color(0xFFB3B3B3),
        focus: Colors.white,
      );

  /// Translucent "glass" surfaces over a soft colorful gradient (no blur: cheap on weak TVs).
  factory Palette.glass(AppAccent a) => Palette(
        dark: true,
        glass: true,
        accent: accentFor(a, true),
        onAccent: onAccentFor(accentFor(a, true)),
        bg: Colors.transparent,
        base: const Color(0xFF141C45),
        panelSolid: const Color(0xFF18235A),
        panel: const Color(0x29FFFFFF),
        surface: const Color(0x1FFFFFFF),
        border: const Color(0x40FFFFFF),
        text: Colors.white,
        muted: const Color(0xCCFFFFFF),
        focus: Colors.white,
      );

  factory Palette.day(AppAccent a) => Palette(
        dark: false,
        accent: accentFor(a, false),
        onAccent: onAccentFor(accentFor(a, false)),
        bg: const Color(0xFFF3F5FA),
        base: const Color(0xFFF3F5FA),
        panelSolid: Colors.white,
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
  String navStyle = 'side'; // side | top | dock
  double sizeFactor = 1.0; // interface size multiplier
  double topInset = 0; // extra top margin (head units whose status bar overlaps the app)
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
    final nav = p.getString('ui.nav');
    navStyle = (nav == 'top' || nav == 'dock') ? nav! : 'side';
    sizeFactor = (p.getDouble('ui.size') ?? 1.0).clamp(0.8, 1.4).toDouble();
    topInset = (p.getDouble('ui.inset') ?? 0).clamp(0.0, 64.0).toDouble();
  }

  Palette resolve(Brightness platform) {
    switch (mode) {
      case AppThemeMode.night:
        return Palette.night(accent);
      case AppThemeMode.black:
        return Palette.black(accent);
      case AppThemeMode.glass:
        return Palette.glass(accent);
      case AppThemeMode.day:
        return Palette.day(accent);
      case AppThemeMode.auto:
        return platform == Brightness.dark ? Palette.night(accent) : Palette.day(accent);
    }
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
    navStyle = 'side';
    sizeFactor = 1.0;
    topInset = 0;
    strings.languageOverride = null;
    notifyListeners();
    for (final k in ['theme.mode', 'theme.accent', 'ui.simple', 'ui.lang', 'ui.nav', 'ui.size', 'ui.inset', 'pref.aspect', 'pref.audio', 'pref.sub']) {
      await _prefs?.remove(k);
    }
  }

  Future<void> setNavStyle(String v) async {
    navStyle = v;
    notifyListeners();
    await _prefs?.setString('ui.nav', v);
  }

  Future<void> setSizeFactor(double v) async {
    sizeFactor = v;
    notifyListeners();
    await _prefs?.setDouble('ui.size', v);
  }

  Future<void> setTopInset(double v) async {
    topInset = v;
    notifyListeners();
    await _prefs?.setDouble('ui.inset', v);
  }

  Future<void> setSimple(bool v) async {
    simple = v;
    notifyListeners();
    await _prefs?.setBool('ui.simple', v);
  }
}

final ThemeController themeController = ThemeController();

/// Carries the size / navigation / margin preferences in the theme so that changing them rebuilds the UI.
@immutable
class UiMetrics extends ThemeExtension<UiMetrics> {
  final double size;
  final String nav;
  final double inset;
  const UiMetrics(this.size, this.nav, this.inset);

  @override
  UiMetrics copyWith({double? size, String? nav, double? inset}) =>
      UiMetrics(size ?? this.size, nav ?? this.nav, inset ?? this.inset);

  @override
  UiMetrics lerp(ThemeExtension<UiMetrics>? other, double t) =>
      (other is UiMetrics && t >= 0.5) ? other : this;
}

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
      surface: p.panelSolid,
      onSurface: p.text,
      surfaceContainerHighest: p.surface,
      outline: p.border,
    ),
    extensions: <ThemeExtension<dynamic>>[
      UiMetrics(themeController.sizeFactor, themeController.navStyle, themeController.topInset),
    ],
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.panelSolid,
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.panelSolid),
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
      backgroundColor: p.panelSolid,
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
    (MediaQuery.of(c).size.height / 540 * themeController.sizeFactor).clamp(0.7, 2.6).toDouble();

/// Explicit sizes already follow [uiScale]; only the simple-mode boost is applied on top.
TextScaler uiTextScaler() => TextScaler.linear(themeController.simple ? 1.2 : 1.0);

/// Soft aurora gradient behind every page in the glass theme (static, no blur).
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16215E), Color(0xFF37206B), Color(0xFF0E4A5C)],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.75, -0.7),
            radius: 0.95,
            colors: [Color(0x55FF7AC6), Color(0x00FF7AC6)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.8, 0.9),
              radius: 0.9,
              colors: [Color(0x4400E5FF), Color(0x0000E5FF)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
