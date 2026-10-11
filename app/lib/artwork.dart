import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'paths.dart';
import 'store.dart';
import 'text_utils.dart';

class ArtRes {
  final String? url;
  final bool cacheable;
  const ArtRes(this.url, this.cacheable);
}

/// Builds normalized-name -> logo URL from the public iptv-org database.
Map<String, String> buildLogoIndex(List<String> bodies) {
  final channels = jsonDecode(bodies[0]);
  final logos = jsonDecode(bodies[1]);
  final best = <String, MapEntry<String, int>>{};
  if (logos is List) {
    for (final l in logos) {
      if (l is! Map) continue;
      final id = l['channel'];
      final url = l['url'];
      if (id is! String || url is! String) continue;
      final w = (l['width'] as num?)?.toInt() ?? 0;
      final h = (l['height'] as num?)?.toInt() ?? 0;
      final area = w * h;
      final cur = best[id];
      if (cur != null && cur.value >= area) continue;
      best[id] = MapEntry(url, area);
    }
  }
  final out = <String, String>{};
  if (channels is List) {
    for (final c in channels) {
      if (c is! Map) continue;
      final id = c['id'];
      if (id is! String) continue;
      final u = best[id]?.key ?? (c['logo'] as String?);
      if (u == null || u.isEmpty) continue;
      final names = <String>[(c['name'] as String?) ?? ''];
      final alt = c['alt_names'];
      if (alt is List) {
        for (final a in alt) {
          if (a is String) names.add(a);
        }
      }
      for (final n in names) {
        final k = TitleCleaner.normalize(n);
        if (k.isNotEmpty) out.putIfAbsent(k, () => u);
      }
    }
  }
  return out;
}

class LogoIndex {
  LogoIndex._();
  static final LogoIndex instance = LogoIndex._();

  Map<String, String> _map = {};
  bool ready = false;
  bool _tried = false;
  Future<void>? _loading;

  Future<void> reset() async {
    try {
      final f = await cacheFile('logo-index.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _map = {};
    ready = false;
    _tried = false;
    _loading = null;
  }

  Future<void> _ensure() {
    if (ready || _tried) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final f = await cacheFile('logo-index.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (m.isNotEmpty) {
          _map = m.map((k, v) => MapEntry(k, v as String));
          ready = true;
          return;
        }
      }
      final res = await Future.wait([
        http.get(Uri.parse('https://iptv-org.github.io/api/channels.json')).timeout(const Duration(seconds: 180)),
        http.get(Uri.parse('https://iptv-org.github.io/api/logos.json')).timeout(const Duration(seconds: 180)),
      ]);
      final built = await compute(buildLogoIndex, [
        utf8.decode(res[0].bodyBytes, allowMalformed: true),
        utf8.decode(res[1].bodyBytes, allowMalformed: true),
      ]);
      _tried = true;
      if (built.isNotEmpty) {
        _map = built;
        ready = true;
        await f.writeAsString(jsonEncode(built));
      }
    } catch (_) {
      _tried = true;
    }
  }

  Future<ArtRes> logo(String name) async {
    await _ensure();
    if (!ready) return const ArtRes(null, false);
    final keys = [
      TitleCleaner.normalize(name),
      TitleCleaner.normalize(LiveName.prefixSplit(name).rest),
      TitleCleaner.normalize(LiveName.clean(name)),
    ];
    for (final k in keys) {
      if (k.isEmpty) continue;
      final u = _map[k];
      if (u != null) return ArtRes(u, true);
    }
    return const ArtRes(null, true);
  }
}

class ArtworkService {
  ArtworkService._();
  static final ArtworkService instance = ArtworkService._();

  Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};
  int _dirty = 0;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;

  String get _tmdbKey => (store.prefs.getString('tmdbKey') ?? '').trim();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await cacheFile('artwork2.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _cache = m.map((k, v) => MapEntry(k, v as String));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await cacheFile('artwork2.json');
      await f.writeAsString(jsonEncode(_cache));
    } catch (_) {}
  }

  Future<void> clear() async {
    _cache = {};
    _loaded = true;
    try {
      final f = await cacheFile('artwork2.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await LogoIndex.instance.reset();
  }

  String _key(Item item) {
    if (item.kind == Kind.live) {
      return 'l|${TitleCleaner.normalize(LiveName.clean(item.name))}';
    }
    final p = TitleCleaner.parse(item.name);
    return '${item.kind.name}|${p.title.toLowerCase()}|${p.year ?? ''}';
  }

  Future<String?> artwork(Item item) async {
    await _ensureLoaded();
    final k = _key(item);
    final c = _cache[k];
    if (c != null) return c.isEmpty ? null : c;
    final running = _inflight[k];
    if (running != null) return running;
    final f = _run(item, k);
    _inflight[k] = f;
    return f;
  }

  Future<String?> _run(Item item, String k) async {
    ArtRes r;
    try {
      r = item.kind == Kind.live ? await LogoIndex.instance.logo(item.name) : await _poster(item);
    } catch (_) {
      r = const ArtRes(null, false);
    }
    if (r.cacheable) {
      _cache[k] = r.url ?? '';
      _dirty++;
      if (_dirty >= 15) {
        _dirty = 0;
        unawaited(_save());
      }
    }
    _inflight.remove(k);
    return r.url;
  }

  Future<ArtRes> _poster(Item item) async {
    final p = TitleCleaner.parse(item.name);
    if (p.title.isEmpty) return const ArtRes(null, true);
    final key = _tmdbKey;
    final series = item.kind == Kind.series;
    if (key.isNotEmpty) return _tmdb(p.title, p.year, series, key);
    return _itunes(p.title, series);
  }

  Future<ArtRes> _tmdb(String title, String? year, bool series, String key) async {
    final bearer = key.startsWith('eyJ');
    final q = <String, String>{'query': title};
    if (year != null) q[series ? 'first_air_date_year' : 'year'] = year;
    if (!bearer) q['api_key'] = key;
    final uri = Uri.parse('https://api.themoviedb.org/3/search/${series ? 'tv' : 'movie'}')
        .replace(queryParameters: q);
    final headers = <String, String>{};
    if (bearer) headers['Authorization'] = 'Bearer $key';
    try {
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 || res.statusCode == 429) return const ArtRes(null, false);
      final root = jsonDecode(utf8.decode(res.bodyBytes));
      final results = root is Map ? root['results'] : null;
      if (results is! List) return const ArtRes(null, false);
      for (final r in results) {
        if (r is Map && r['poster_path'] is String) {
          return ArtRes('https://image.tmdb.org/t/p/w342${r['poster_path']}', true);
        }
      }
      if (year != null) return _tmdb(title, null, series, key);
      return const ArtRes(null, true);
    } catch (_) {
      return const ArtRes(null, false);
    }
  }

  Future<ArtRes> _itunes(String title, bool series) async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(const Duration(milliseconds: 1200));
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future.delayed(wait);
    final uri = Uri.parse('https://itunes.apple.com/search').replace(queryParameters: {
      'term': title,
      'media': series ? 'tvShow' : 'movie',
      'entity': series ? 'tvSeason' : 'movie',
      'limit': '5',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const ArtRes(null, false);
      final root = jsonDecode(utf8.decode(res.bodyBytes));
      final results = root is Map ? root['results'] : null;
      if (results is! List) return const ArtRes(null, false);
      final target = TitleCleaner.normalize(title);
      for (final r in results) {
        if (r is! Map) continue;
        final n = TitleCleaner.normalize((r['trackName'] ?? r['collectionName'] ?? '').toString());
        final art = r['artworkUrl100'];
        if (n.isNotEmpty && (n.contains(target) || target.contains(n)) && art is String) {
          return ArtRes(art.replaceAll('100x100bb', '400x600bb'), true);
        }
      }
      return const ArtRes(null, true);
    } catch (_) {
      return const ArtRes(null, false);
    }
  }
}
