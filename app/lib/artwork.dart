import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'paths.dart';
import 'store.dart';
import 'strings.dart' show isArabic;
import 'text_utils.dart';

const String _builtInTmdbKey = String.fromEnvironment('TMDB_KEY');

class ArtRes {
  final String? url;
  final bool cacheable;
  const ArtRes(this.url, this.cacheable);
}

final RegExp _objRe = RegExp(r'\{[^{}]*\}');
final RegExp _chanRe = RegExp(r'"channel"\s*:\s*"((?:[^"\\]|\\.)*)"');
final RegExp _urlRe = RegExp(r'"url"\s*:\s*"((?:[^"\\]|\\.)*)"');
final RegExp _wRe = RegExp(r'"width"\s*:\s*(\d+)');
final RegExp _hRe = RegExp(r'"height"\s*:\s*(\d+)');
final RegExp _idRe = RegExp(r'"id"\s*:\s*"((?:[^"\\]|\\.)*)"');
final RegExp _nameRe = RegExp(r'"name"\s*:\s*"((?:[^"\\]|\\.)*)"');
final RegExp _altRe = RegExp(r'"alt_names"\s*:\s*\[([^\]]*)\]');
final RegExp _logoRe = RegExp(r'"logo"\s*:\s*"((?:[^"\\]|\\.)*)"');

String _un(String s) {
  if (!s.contains('\\')) return s;
  try {
    return jsonDecode('"$s"') as String;
  } catch (_) {
    return s;
  }
}

/// Builds normalized-name -> logo URL from the public iptv-org database.
/// Uses regex scanning (not a full JSON parse) to keep memory low on weak TV boxes.
Map<String, String> buildLogoIndex(List<String> bodies) {
  final best = <String, MapEntry<String, int>>{};
  for (final m in _objRe.allMatches(bodies[1])) {
    final o = m.group(0)!;
    final id = _chanRe.firstMatch(o)?.group(1);
    final url = _urlRe.firstMatch(o)?.group(1);
    if (id == null || url == null) continue;
    final w = int.tryParse(_wRe.firstMatch(o)?.group(1) ?? '') ?? 0;
    final h = int.tryParse(_hRe.firstMatch(o)?.group(1) ?? '') ?? 0;
    final key = _un(id);
    final area = w * h;
    final cur = best[key];
    if (cur != null && cur.value >= area) continue;
    best[key] = MapEntry(_un(url), area);
  }
  final out = <String, String>{};
  for (final m in _objRe.allMatches(bodies[0])) {
    final o = m.group(0)!;
    final id = _idRe.firstMatch(o)?.group(1);
    if (id == null) continue;
    final logoRaw = _logoRe.firstMatch(o)?.group(1);
    final u = best[_un(id)]?.key ?? (logoRaw == null ? null : _un(logoRaw));
    if (u == null || u.isEmpty) continue;
    final names = <String>[];
    final nm = _nameRe.firstMatch(o)?.group(1);
    if (nm != null) names.add(_un(nm));
    final alt = _altRe.firstMatch(o)?.group(1);
    if (alt != null && alt.trim().isNotEmpty) {
      try {
        final l = jsonDecode('[$alt]');
        if (l is List) {
          for (final a in l) {
            if (a is String) names.add(a);
          }
        }
      } catch (_) {}
    }
    for (final n in names) {
      final k = TitleCleaner.normalize(n);
      if (k.isNotEmpty) out.putIfAbsent(k, () => u);
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

/// Backdrop image path + overview from TMDB (used by the TV home hero / cards).
class ArtMeta {
  final String? backdropPath;
  final String? overview;
  const ArtMeta(this.backdropPath, this.overview);
}

class ArtworkService {
  ArtworkService._();
  static final ArtworkService instance = ArtworkService._();

  Map<String, String> _cache = {};
  final Map<String, Future<String?>> _inflight = {};
  int _dirty = 0;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loaded = false;

  String get _tmdbKey {
    final user = (store.prefs.getString('tmdbKey') ?? '').trim();
    return user.isEmpty ? _builtInTmdbKey : user;
  }

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

  final Map<String, Future<ArtMeta?>> _metaCache = {};

  /// Backdrop + overview for movies/series. Returns null without a TMDB key or for live channels.
  Future<ArtMeta?> meta(Item item) {
    if (item.kind == Kind.live) return Future<ArtMeta?>.value(null);
    final key = _tmdbKey;
    if (key.isEmpty) return Future<ArtMeta?>.value(null);
    return _metaCache.putIfAbsent('${_key(item)}|meta', () => _fetchMeta(item, key));
  }

  Future<ArtMeta?> _fetchMeta(Item item, String key) async {
    final p = TitleCleaner.parse(item.name);
    if (p.title.isEmpty) return null;
    final series = item.kind == Kind.series;
    try {
      var m = await _tmdbMeta(p.title, p.year, series, key, isArabic ? 'ar' : 'en-US');
      if (isArabic && (m == null || (m.overview ?? '').isEmpty)) {
        final en = await _tmdbMeta(p.title, p.year, series, key, 'en-US');
        if (en != null) m = ArtMeta(m?.backdropPath ?? en.backdropPath, en.overview);
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<ArtMeta?> _tmdbMeta(String title, String? year, bool series, String key, String lang) async {
    final bearer = key.startsWith('eyJ');
    final q = <String, String>{'query': title, 'language': lang};
    if (year != null) q[series ? 'first_air_date_year' : 'year'] = year;
    if (!bearer) q['api_key'] = key;
    final uri = Uri.parse('https://api.themoviedb.org/3/search/${series ? 'tv' : 'movie'}')
        .replace(queryParameters: q);
    final headers = <String, String>{};
    if (bearer) headers['Authorization'] = 'Bearer $key';
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final root = jsonDecode(utf8.decode(res.bodyBytes));
    final results = root is Map ? root['results'] : null;
    if (results is! List) return null;
    for (final r in results) {
      if (r is Map && r['backdrop_path'] is String) {
        return ArtMeta(r['backdrop_path'] as String, r['overview'] as String?);
      }
    }
    if (year != null) return _tmdbMeta(title, null, series, key, lang);
    return null;
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
      if (year != null) return await _tmdb(title, null, series, key);
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
