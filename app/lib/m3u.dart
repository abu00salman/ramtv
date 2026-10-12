import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'text_utils.dart';

dynamic _decode(String s) => jsonDecode(s);

class M3UArgs {
  final String text;
  final String sourceId;
  const M3UArgs(this.text, this.sourceId);
}

String? _attr(String key, String line) {
  final m = RegExp('$key="([^"]*)"').firstMatch(line);
  final v = m?.group(1)?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

List<Item> parseM3U(M3UArgs a) {
  final items = <Item>[];
  String? name;
  String? logo;
  String group = 'Other';

  var firstLine = true;
  for (final raw in LineSplitter.split(a.text)) {
    final line = (firstLine ? raw.replaceFirst('\uFEFF', '') : raw).trim();
    firstLine = false;
    if (line.startsWith('#EXTINF')) {
      // Metadata can contain commas in quoted attributes; titles can too.
      var quoted = false;
      var idx = -1;
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '"') quoted = !quoted;
        if (line[i] == ',' && !quoted) {
          idx = i;
          break;
        }
      }
      name = idx >= 0 ? line.substring(idx + 1).trim() : 'Channel';
      logo = _attr('tvg-logo', line);
      group = _attr('group-title', line) ?? 'Other';
    } else if (line.isNotEmpty && !line.startsWith('#') && name != null) {
      final lower = (Uri.tryParse(line)?.path ?? line).toLowerCase();
      Kind kind;
      if (lower.contains('/series/')) {
        kind = Kind.series;
      } else if (lower.contains('/movie/') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.avi')) {
        kind = Kind.movie;
      } else {
        kind = Kind.live;
      }
      final nm = name;
      items.add(Item(
        id: '${kind.name}|$line',
        name: nm.isEmpty ? 'Channel' : nm,
        logo: logo,
        group: group,
        url: line,
        kind: kind,
        sourceId: a.sourceId,
      ));
      name = null;
      logo = null;
      group = 'Other';
    }
  }
  return _autoGroup(items);
}

/// Playlists without group-title: derive groups from the name prefix ("STC TV: ...") or first word.
List<Item> _autoGroup(List<Item> items) {
  final counts = <String, int>{};
  final display = <String, String>{};
  final cand = <int, String>{};
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.group != 'Other' || it.kind != Kind.live) continue;
    final sp = LiveName.prefixSplit(it.name);
    final first = it.name.trim().split(' ').first;
    final c = (sp.prefix ?? first).trim();
    final k = c.toLowerCase();
    if (k.length >= 2) {
      cand[i] = k;
      counts[k] = (counts[k] ?? 0) + 1;
      display.putIfAbsent(k, () => c);
    }
  }
  cand.forEach((i, k) {
    if ((counts[k] ?? 0) >= 3) items[i].group = display[k] ?? k;
  });
  return items;
}

Future<List<Item>> loadM3U(Source s, {http.Client? client}) async {
  final uri = Uri.parse(s.url.trim());
  final res = await (client?.get(uri, headers: {'User-Agent': 'RaMtv/1.0'}) ??
          http.get(uri, headers: {'User-Agent': 'RaMtv/1.0'}))
      .timeout(const Duration(seconds: 120));
  if (res.statusCode >= 400) {
    throw Exception('HTTP ${res.statusCode}');
  }
  return compute(_decodeM3U, _M3UBytes(res.bodyBytes, s.id));
}

class _M3UBytes {
  final List<int> bytes;
  final String sourceId;
  const _M3UBytes(this.bytes, this.sourceId);
}

List<Item> _decodeM3U(_M3UBytes args) => parseM3U(
    M3UArgs(utf8.decode(args.bytes, allowMalformed: true), args.sourceId));

class _XtreamCatalogue {
  final Source source;
  final List<dynamic> responses;
  const _XtreamCatalogue(this.source, this.responses);
}

List<Item> _parseXtreamCatalogue(_XtreamCatalogue args) =>
    XtreamClient(args.source).parseCatalogue(args.responses, args.source.id);

class XtreamClient {
  final http.Client? client;
  final Source source;
  final String base;
  final String user;
  final String pass;

  XtreamClient(Source s, {this.client})
      : source = s,
        base = _norm(s.url),
        user = s.username,
        pass = s.password;

  static String _norm(String u) {
    var b = u.trim();
    if (!b.toLowerCase().startsWith('http')) b = 'http://$b';
    for (final suf in ['/player_api.php', '/get.php']) {
      final i = b.indexOf(suf);
      if (i >= 0) b = b.substring(0, i);
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  String _s(dynamic v) => v == null ? '' : v.toString();

  Future<dynamic> call(
      [String? action, Map<String, String> extra = const {}]) async {
    final q = <String, String>{'username': user, 'password': pass};
    if (action != null) q['action'] = action;
    q.addAll(extra);
    final uri = Uri.parse('$base/player_api.php').replace(queryParameters: q);
    final res = await (client?.get(uri, headers: {'User-Agent': 'RaMtv/1.0'}) ??
            http.get(uri, headers: {'User-Agent': 'RaMtv/1.0'}))
        .timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return compute(_decode, utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  Future<dynamic> _try(String action) async {
    try {
      return await call(action);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _cats(dynamic any) {
    final m = <String, String>{};
    if (any is List) {
      for (final d in any) {
        if (d is Map) m[_s(d['category_id'])] = _s(d['category_name']);
      }
    }
    return m;
  }

  Future<List<Item>> fetchAll(String sourceId) async {
    final login = await call();
    if (login is Map && login['user_info'] is Map) {
      final auth = _s((login['user_info'] as Map)['auth']);
      if (auth == '0') {
        throw Exception('Login failed. Check username and password.');
      }
    }

    final results = await Future.wait([
      _try('get_live_categories'),
      _try('get_live_streams'),
      _try('get_vod_categories'),
      _try('get_vod_streams'),
      _try('get_series_categories'),
      _try('get_series'),
    ]);

    return compute(_parseXtreamCatalogue, _XtreamCatalogue(source, results));
  }

  List<Item> parseCatalogue(List<dynamic> results, String sourceId) {
    final tag = sourceId.length > 8 ? sourceId.substring(0, 8) : sourceId;
    final out = <Item>[];

    final lcm = _cats(results[0]);
    if (results[1] is List) {
      for (final d in results[1] as List) {
        if (d is! Map) continue;
        final id = _s(d['stream_id']);
        if (id.isEmpty) continue;
        final icon = _s(d['stream_icon']);
        out.add(Item(
          id: '$tag-live-$id',
          name: _s(d['name']),
          logo: icon.isEmpty ? null : icon,
          group: lcm[_s(d['category_id'])] ?? 'Live',
          url: '$base/live/$user/$pass/$id.m3u8',
          kind: Kind.live,
          sourceId: sourceId,
        ));
      }
    }

    final vcm = _cats(results[2]);
    if (results[3] is List) {
      for (final d in results[3] as List) {
        if (d is! Map) continue;
        final id = _s(d['stream_id']);
        if (id.isEmpty) continue;
        final ext = _s(d['container_extension']).isEmpty
            ? 'mp4'
            : _s(d['container_extension']);
        final icon = _s(d['stream_icon']);
        out.add(Item(
          id: '$tag-vod-$id',
          name: _s(d['name']),
          logo: icon.isEmpty ? null : icon,
          group: vcm[_s(d['category_id'])] ?? 'Movies',
          url: '$base/movie/$user/$pass/$id.$ext',
          kind: Kind.movie,
          sourceId: sourceId,
        ));
      }
    }

    final scm = _cats(results[4]);
    if (results[5] is List) {
      for (final d in results[5] as List) {
        if (d is! Map) continue;
        final id = _s(d['series_id']);
        if (id.isEmpty) continue;
        final cover = _s(d['cover']);
        out.add(Item(
          id: '$tag-series-$id',
          name: _s(d['name']),
          logo: cover.isEmpty ? null : cover,
          group: scm[_s(d['category_id'])] ?? 'Series',
          kind: Kind.series,
          seriesId: id,
          sourceId: sourceId,
        ));
      }
    }
    return out;
  }

  Future<List<Episode>> episodes(String seriesId) async {
    final root = await call('get_series_info', {'series_id': seriesId});
    if (root is! Map) return [];
    final seasons = <MapEntry<int, List<dynamic>>>[];
    final eps = root['episodes'];
    if (eps is Map) {
      eps.forEach((k, v) {
        seasons.add(MapEntry(
            int.tryParse(k.toString()) ?? 0, v is List ? v : <dynamic>[]));
      });
    } else if (eps is List) {
      for (var i = 0; i < eps.length; i++) {
        final v = eps[i];
        seasons.add(MapEntry(i + 1, v is List ? v : <dynamic>[]));
      }
    }
    final out = <Episode>[];
    for (final s in seasons) {
      for (final e in s.value) {
        if (e is! Map) continue;
        final id = _s(e['id']);
        if (id.isEmpty) continue;
        final ext = _s(e['container_extension']).isEmpty
            ? 'mp4'
            : _s(e['container_extension']);
        final title = _s(e['title']).isEmpty ? 'Episode' : _s(e['title']);
        out.add(Episode(
          id: id,
          title: title,
          url: '$base/series/$user/$pass/$id.$ext',
          season: s.key,
          number: int.tryParse(_s(e['episode_num'])) ?? 0,
        ));
      }
    }
    out.sort((a, b) {
      final c = a.season.compareTo(b.season);
      return c != 0 ? c : a.number.compareTo(b.number);
    });
    return out;
  }
}

List<Item> demoItems(String sourceId) {
  Item mk(String name, String url, Kind kind) => Item(
        id: 'demo|$url',
        name: name,
        group: 'Demo',
        url: url,
        kind: kind,
        sourceId: sourceId,
      );
  return [
    mk(
        'Apple Test Stream',
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
        Kind.live),
    mk('Mux Test Stream', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        Kind.live),
    mk(
        'Sintel',
        'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
        Kind.movie),
    mk(
        'Apple BipBop 16:9',
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8',
        Kind.movie),
  ];
}
