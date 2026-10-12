import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/epg.dart';

void main() {
  test('decodes Arabic titles and observes exact UTC programme boundaries', () {
    final programs = parseXtreamEpg({
      'epg_listings': [
        {
          'title': base64.encode(utf8.encode('أخبار')),
          'start_timestamp': '100',
          'stop_timestamp': '200'
        },
        {'title': 'Broken', 'start_timestamp': '200', 'stop_timestamp': '100'},
        {'title': 'Missing times'},
      ]
    });
    expect(programs.single.title, 'أخبار');
    expect(
        programs.single.isCurrent(
            DateTime.fromMillisecondsSinceEpoch(100000, isUtc: true)),
        isTrue);
    expect(
        programs.single.isCurrent(
            DateTime.fromMillisecondsSinceEpoch(200000, isUtc: true)),
        isFalse);
  });

  test('cache isolates providers, expires entries and bounds memory', () {
    var now = DateTime.utc(2026);
    final cache = EpgCache(capacity: 2, now: () => now);
    cache.put('provider-a|42', []);
    expect(cache.get('provider-b|42'), isNull);
    cache.put('provider-b|42', []);
    cache.put('provider-c|42', []);
    expect(cache.get('provider-a|42'), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(cache.get('provider-c|42'), isNull);
  });

  test('missing EPG is optional', () {
    expect(parseXtreamEpg(null), isEmpty);
    expect(parseXtreamEpg({'epg_listings': []}), isEmpty);
  });
}
