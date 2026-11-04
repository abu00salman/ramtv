import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ramtv/models.dart';
import 'package:ramtv/store.dart';
import 'package:ramtv/text_utils.dart';
import 'package:ramtv/theme.dart';
import 'package:ramtv/ui/widgets.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

KeyEvent _down(LogicalKeyboardKey k) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.enter, logicalKey: k, timeStamp: Duration.zero);
KeyEvent _rep(LogicalKeyboardKey k) => KeyRepeatEvent(
    physicalKey: PhysicalKeyboardKey.enter, logicalKey: k, timeStamp: Duration.zero);
KeyEvent _up(LogicalKeyboardKey k) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.enter, logicalKey: k, timeStamp: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Arabic search ignores diacritics and letter variants', () {
    expect(normalizeSearch('أَطْفَال'), normalizeSearch('اطفال'));
    expect(normalizeSearch('مدرسة'), normalizeSearch('مدرسه'));
    expect(normalizeSearch('beIN  Sport-1'), 'bein sport 1');
    final i = Item(
        id: 'a', name: 'قناة الأطفال HD', group: 'Kids', kind: Kind.live, sourceId: 's');
    expect(searchKey(i).contains(normalizeSearch('اطفال')), isTrue);
  });

  test('theme choices persist and every palette has readable contrast', () async {
    final p = await SharedPreferences.getInstance();
    final c = ThemeController()..load(p);
    await c.setMode(AppThemeMode.day);
    await c.setAccent(AppAccent.purple);
    await c.setSimple(true);
    final again = ThemeController()..load(p);
    expect(again.mode, AppThemeMode.day);
    expect(again.accent, AppAccent.purple);
    expect(again.simple, isTrue);
    expect(again.resolve(Brightness.dark).dark, isFalse);
    final auto = ThemeController()..mode = AppThemeMode.auto;
    expect(auto.resolve(Brightness.dark).dark, isTrue);
    expect(auto.resolve(Brightness.light).dark, isFalse);
    for (final a in AppAccent.values) {
      for (final pal in [
        Palette.night(a),
        Palette.black(a),
        Palette.glass(a),
        Palette.day(a)
      ]) {
        expect(_contrast(pal.text, pal.base), greaterThan(7));
        expect(_contrast(pal.text, pal.panelSolid), greaterThan(7));
        expect(_contrast(pal.onAccent, pal.accent), greaterThan(3));
        expect(_contrast(pal.focus, pal.base), greaterThan(7));
      }
    }
  });

  test('every accent is visible on every background and its label is readable', () {
    expect(AppAccent.values.length, greaterThanOrEqualTo(10));
    for (final a in AppAccent.values) {
      for (final pal in [Palette.night(a), Palette.black(a), Palette.glass(a), Palette.day(a)]) {
        expect(_contrast(pal.accent, pal.base), greaterThan(3), reason: '$a on ${pal.base}');
        expect(_contrast(pal.onAccent, pal.accent), greaterThan(4.5), reason: '$a label');
      }
    }
  });

  test('navigation style, interface size and top margin persist and are clamped', () async {
    final p = await SharedPreferences.getInstance();
    final c = ThemeController()..load(p);
    expect(c.navStyle, 'side');
    expect(c.sizeFactor, 1.0);
    expect(c.topInset, 0);
    await c.setNavStyle('dock');
    await c.setSizeFactor(1.15);
    await c.setTopInset(32);
    final again = ThemeController()..load(p);
    expect(again.navStyle, 'dock');
    expect(again.sizeFactor, 1.15);
    expect(again.topInset, 32);
    await p.setString('ui.nav', 'unknown');
    await p.setDouble('ui.size', 9);
    await p.setDouble('ui.inset', -5);
    final bad = ThemeController()..load(p);
    expect(bad.navStyle, 'side');
    expect(bad.sizeFactor, 1.4);
    expect(bad.topInset, 0);
    await again.resetAll();
    expect(again.navStyle, 'side');
    expect(again.sizeFactor, 1.0);
  });

  test('OK key: one action per press, long press only after holding', () async {
    var taps = 0;
    var longs = 0;
    final plain = SelectKeyHandler(onTap: () => taps++);
    plain.handle(_down(LogicalKeyboardKey.enter));
    plain.handle(_rep(LogicalKeyboardKey.enter));
    plain.handle(_up(LogicalKeyboardKey.enter));
    expect(taps, 1);

    final withLong = SelectKeyHandler(onTap: () => taps++, onLongPress: () => longs++);
    withLong.handle(_down(LogicalKeyboardKey.select));
    withLong.handle(_up(LogicalKeyboardKey.select));
    expect(taps, 2);
    expect(longs, 0);

    withLong.handle(_down(LogicalKeyboardKey.select));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    withLong.handle(_rep(LogicalKeyboardKey.select));
    withLong.handle(_up(LogicalKeyboardKey.select));
    expect(longs, 1);
    expect(taps, 2);
  });

  test('active source and kids mode filter the catalogue; PIN is checked', () async {
    final store = AppStore();
    await store.init();
    store.sources.add(const Source(id: 'demo1', name: 'Demo', type: 'demo', url: ''));
    await store.refresh();
    expect(store.items, isNotEmpty);
    store.setActiveSource('other');
    expect(store.items, isEmpty);
    store.setActiveSource(null);
    expect(store.items, isNotEmpty);
    store.setPin('1234');
    expect(store.checkPin('1234'), isTrue);
    expect(store.checkPin('0000'), isFalse);
    store.setKidsMode(true);
    expect(store.items, isEmpty);
    store.setKidsMode(false);
    expect(store.items, isNotEmpty);
    store.dispose();
  });
}
