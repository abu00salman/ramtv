import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ramtv/models.dart';
import 'package:ramtv/store.dart';

const source = Source(
  id: 'source',
  name: 'Provider',
  type: 'm3u',
  url: 'https://example.test/list',
);
http.Response playlist(String title) =>
    http.Response('#EXTINF:-1,$title\nhttps://example.test/live.ts', 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('corrupt persisted entries do not prevent startup', () async {
    SharedPreferences.setMockInitialValues({
      'sources': jsonEncode([
        {'broken': true},
        source.toJson()
      ]),
      'recents': '{invalid',
      'resume': jsonEncode({
        'bad': ['text', 30],
        'valid': [40, 100]
      }),
    });
    final store = AppStore();
    await store.init();
    expect(store.sources.single.id, source.id);
    expect(store.recents, isEmpty);
    expect(store.getResume('bad'), isNull);
    expect(store.getResume('valid'), [40, 100]);
    store.dispose();
  });

  test('an older refresh cannot overwrite the latest catalogue', () async {
    final older = Completer<http.Response>();
    var count = 0;
    final store = AppStore(
        clientFactory: () => MockClient((_) {
              count++;
              return count == 1
                  ? older.future
                  : Future.value(playlist('Latest'));
            }));
    await store.init();
    store.sources.add(source);
    final first = store.refresh();
    await Future<void>.delayed(Duration.zero);
    await store.refresh();
    older.complete(playlist('Old'));
    await first;
    expect(store.live.single.name, 'Latest');
    expect(store.loading, isFalse);
    store.dispose();
  });

  test('network failure retains the last provider catalogue and hides URLs',
      () async {
    var fail = false;
    final store = AppStore(
        clientFactory: () => MockClient((_) async {
              if (fail) throw StateError('https://secret.test/password');
              return playlist('Available');
            }));
    await store.init();
    store.sources.add(source);
    await store.refresh();
    fail = true;
    await store.refresh();
    expect(store.live.single.name, 'Available');
    expect(store.error, isNot(contains('secret.test')));
    expect(store.loading, isFalse);
    store.dispose();
  });

  test('removing all providers clears data and loading state', () async {
    final store = AppStore(
        clientFactory: () => MockClient((_) async => playlist('Channel')));
    await store.init();
    store.sources.add(source);
    await store.refresh();
    store.sources.clear();
    await store.refresh();
    expect(store.items, isEmpty);
    expect(store.loading, isFalse);
    store.dispose();
  });
}
