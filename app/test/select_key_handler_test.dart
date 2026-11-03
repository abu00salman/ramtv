import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/ui/widgets.dart';

KeyEvent _ev(String kind) {
  const p = PhysicalKeyboardKey.select;
  const l = LogicalKeyboardKey.select;
  const t = Duration.zero;
  switch (kind) {
    case 'down':
      return const KeyDownEvent(physicalKey: p, logicalKey: l, timeStamp: t);
    case 'repeat':
      return const KeyRepeatEvent(physicalKey: p, logicalKey: l, timeStamp: t);
    default:
      return const KeyUpEvent(physicalKey: p, logicalKey: l, timeStamp: t);
  }
}

void main() {
  test('release of a press that began elsewhere does not activate the row', () {
    var taps = 0, longs = 0;
    final h = SelectKeyHandler(onTap: () => taps++, onLongPress: () => longs++);
    h.handle(_ev('repeat'));
    h.handle(_ev('up'));
    expect(taps, 0);
    expect(longs, 0);
  });

  test('a full short press on the row activates it once', () {
    var taps = 0;
    final h = SelectKeyHandler(onTap: () => taps++, onLongPress: () {});
    h.handle(_ev('down'));
    h.handle(_ev('up'));
    expect(taps, 1);
    h.handle(_ev('up'));
    expect(taps, 1);
  });

  test('rows without a long-press action still activate on key down', () {
    var taps = 0;
    final h = SelectKeyHandler(onTap: () => taps++);
    h.handle(_ev('down'));
    expect(taps, 1);
    h.handle(_ev('up'));
    expect(taps, 1);
  });
}
