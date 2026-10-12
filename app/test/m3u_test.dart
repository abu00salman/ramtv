import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ramtv/m3u.dart';
import 'package:ramtv/models.dart';

void main() {
  test('large playlists preserve all channel entries', () {
    final text = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < 20000; i++) {
      text.writeln('#EXTINF:-1 group-title="News",Channel $i');
      text.writeln('https://example.test/$i.ts');
    }
    final items = parseM3U(M3UArgs(text.toString(), 'provider'));
    expect(items.length, 20000);
    expect(items.last.name, 'Channel 19999');
  });

  test('Xtream builds its catalogue in an isolate with an owned HTTP client',
      () async {
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action'];
      final dynamic payload;
      if (action == null) {
        payload = {
          'user_info': {'auth': 1}
        };
      } else if (action == 'get_live_streams') {
        payload = [
          {'stream_id': 42, 'name': 'Channel', 'category_id': 1}
        ];
      } else if (action == 'get_live_categories') {
        payload = [
          {'category_id': 1, 'category_name': 'News'}
        ];
      } else {
        payload = [];
      }
      return http.Response(jsonEncode(payload), 200);
    });
    final items = await XtreamClient(
            const Source(
              id: 'provider',
              name: 'Server',
              type: 'xtream',
              url: 'https://example.test',
              username: 'test',
              password: 'fixture',
            ),
            client: client)
        .fetchAll('provider');
    expect(items.single.group, 'News');
    expect(items.single.kind, Kind.live);
    client.close();
  });
  test('preserves commas in titles and quoted metadata', () {
    final items = parseM3U(const M3UArgs(
        '#EXTM3U\n#EXTINF:-1 group-title="News, World",News, Arabic\n'
            'https://example.test/live.m3u8\n',
        'provider'));
    expect(items.single.name, 'News, Arabic');
    expect(items.single.group, 'News, World');
  });

  test('classifies movie paths independently of query tokens', () {
    final items = parseM3U(const M3UArgs(
        '#EXTINF:-1,Movie\nhttps://example.test/video.MKV?token=test\n',
        'provider'));
    expect(items.single.kind, Kind.movie);
  });

  test('handles BOM, CRLF and missing stream entries', () {
    final items = parseM3U(const M3UArgs(
        '\uFEFF#EXTM3U\r\n#EXTINF:-1,Missing\r\n'
            '#EXTINF:-1,Channel\r\nhttps://example.test/live.ts\r\n',
        'provider'));
    expect(items.single.name, 'Channel');
    expect(items.single.kind, Kind.live);
  });
}
