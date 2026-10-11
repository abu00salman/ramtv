import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'm3u.dart';
import 'paths.dart';
import 'text_utils.dart';

String _encodeItems(List<Item> l) => jsonEncode(l.map((e) => e.toJson()).toList());

List<Item> _decodeItems(String s) => (jsonDecode(s) as List)
    .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

class PlayRequest {
  final String title;
  final String url;
  final bool isLive;
  final Item? item;
  final String? resumeKey;
  final bool isEpisode;
  const PlayRequest({
    required this.title,
    required this.url,
    this.isLive = false,
    this.item,
    this.resumeKey,
    this.isEpisode = false,
  });
}

class AppStore extends ChangeNotifier {
  List<Source> sources = [];
  List<Item> items = [];
  List<Item> live = [];
  List<Item> movies = [];
  List<Item> series = [];
  List<String> liveGroups = [];
  Set<String> favorites = {};
  List<Item> recents = [];
  bool loading = false;
  String? error;

  List<Item> queue = [];
  int queueIndex = 0;
  List<Episode> epQueue = [];
  int epIndex = 0;
  String epSeries = '';
  PlayRequest? lastRequest;

  late SharedPreferences prefs;
  Map<String, List<double>> _resume = {};

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('sources');
    if (s != null) {
      sources = (jsonDecode(s) as List)
          .map((e) => Source.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    favorites = (prefs.getStringList('favorites') ?? <String>[]).toSet();
    final r = prefs.getString('recents');
    if (r != null) {
      recents = (jsonDecode(r) as List)
          .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final rs = prefs.getString('resume');
    if (rs != null) {
      final m = jsonDecode(rs) as Map<String, dynamic>;
      _resume = m.map((k, v) =>
          MapEntry(k, (v as List).map((x) => (x as num).toDouble()).toList()));
    }
    try {
      final f = await cacheFile('items.json');
      if (await f.exists()) {
        final txt = await f.readAsString();
        final list = await compute(_decodeItems, txt);
        _setItems(list);
      }
    } catch (_) {}
  }

  Future<void> bootstrap() async {
    if (sources.isEmpty) return;
    final last = prefs.getInt('lastRefresh') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    if (items.isEmpty || age > 6 * 3600 * 1000 || (prefs.getInt('dataVersion') ?? 0) != 3) {
      await refresh();
    }
  }

  // ---------- Sources ----------

  void _saveSources() {
    prefs.setString('sources', jsonEncode(sources.map((e) => e.toJson()).toList()));
  }

  void addSource(Source s) {
    sources.add(s);
    _saveSources();
    notifyListeners();
    refresh();
  }

  String newId() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  void addDemo() => addSource(Source(id: newId(), name: 'Demo', type: 'demo', url: ''));

  void removeSource(String id) {
    sources.removeWhere((e) => e.id == id);
    _saveSources();
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    if (sources.isEmpty) {
      _setItems([]);
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final all = <Item>[];
    for (final s in sources) {
      try {
        if (s.type == 'm3u') {
          all.addAll(await loadM3U(s));
        } else if (s.type == 'xtream') {
          all.addAll(await XtreamClient(s).fetchAll(s.id));
        } else {
          all.addAll(demoItems(s.id));
        }
      } catch (e) {
        error = '${s.name}: $e';
      }
    }
    _setItems(all);
    loading = false;
    if (error == null) {
      prefs.setInt('lastRefresh', DateTime.now().millisecondsSinceEpoch);
      prefs.setInt('dataVersion', 3);
    }
    notifyListeners();
    unawaited(_saveCache(all));
  }

  Future<void> _saveCache(List<Item> all) async {
    try {
      final txt = await compute(_encodeItems, all);
      final f = await cacheFile('items.json');
      await f.writeAsString(txt);
    } catch (_) {}
  }

  void _setItems(List<Item> list) {
    final seen = <String>{};
    final unique = <Item>[];
    for (final i in list) {
      if (seen.add(i.id)) unique.add(i);
    }
    items = unique;
    live = unique.where((e) => e.kind == Kind.live).toList();
    movies = unique.where((e) => e.kind == Kind.movie).toList();
    series = unique.where((e) => e.kind == Kind.series).toList();
    final gs = <String>{};
    final groups = <String>[];
    for (final i in live) {
      if (gs.add(i.group)) groups.add(i.group);
    }
    liveGroups = groups;
  }

  Item? get heroItem {
    if (recents.isNotEmpty) return recents.first;
    for (final m in movies) {
      if (m.logo != null && m.url != null) return m;
    }
    if (movies.isNotEmpty) return movies.first;
    return live.isNotEmpty ? live.first : null;
  }

  List<Item> get favoriteItems => items.where((e) => favorites.contains(e.id)).toList();

  bool isFavorite(Item i) => favorites.contains(i.id);

  void toggleFavorite(Item i) {
    if (!favorites.remove(i.id)) favorites.add(i.id);
    prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
  }

  // ---------- Playback queues ----------

  PlayRequest? _request(Item item) {
    final u = item.url;
    if (u == null) return null;
    return PlayRequest(
      title: item.displayTitle,
      url: u,
      isLive: item.kind == Kind.live,
      item: item,
      resumeKey: item.kind == Kind.live ? null : item.id,
    );
  }

  void _touchRecents(Item item) {
    recents.removeWhere((e) => e.id == item.id);
    recents.insert(0, item);
    if (recents.length > 20) recents = recents.sublist(0, 20);
    prefs.setString('recents', jsonEncode(recents.map((e) => e.toJson()).toList()));
  }

  PlayRequest? prepare(Item item, {List<Item>? list}) {
    final r = _request(item);
    if (r == null) return null;
    if (item.kind == Kind.live) {
      queue = list ?? live.where((e) => e.group == item.group).toList();
      final i = queue.indexWhere((e) => e.id == item.id);
      queueIndex = i < 0 ? 0 : i;
    } else {
      queue = [];
    }
    epQueue = [];
    lastRequest = r;
    _touchRecents(item);
    notifyListeners();
    return r;
  }

  bool get canStep => queue.length > 1 || epQueue.length > 1;

  PlayRequest? zap(int delta) {
    if (epQueue.isNotEmpty) {
      final n = epIndex + delta;
      if (n < 0 || n >= epQueue.length) return null;
      epIndex = n;
      final r = _episodeRequest(epQueue[n]);
      lastRequest = r;
      return r;
    }
    if (queue.isEmpty) return null;
    queueIndex = (queueIndex + delta + queue.length) % queue.length;
    return _startQueued(queue[queueIndex]);
  }

  PlayRequest? jump(Item item) {
    final i = queue.indexWhere((e) => e.id == item.id);
    if (i >= 0) queueIndex = i;
    return _startQueued(item);
  }

  PlayRequest? _startQueued(Item item) {
    final r = _request(item);
    if (r == null) return null;
    lastRequest = r;
    _touchRecents(item);
    return r;
  }

  PlayRequest _episodeRequest(Episode e) {
    final label = epSeries.isEmpty ? e.title : '$epSeries S${e.season}E${e.number}';
    return PlayRequest(
      title: label,
      url: e.url,
      isLive: false,
      resumeKey: 'ep|${e.id}',
      isEpisode: true,
    );
  }

  PlayRequest prepareEpisode(Episode e, List<Episode> list, String seriesTitle) {
    queue = [];
    epQueue = list;
    final i = list.indexWhere((x) => x.id == e.id);
    epIndex = i < 0 ? 0 : i;
    epSeries = seriesTitle;
    final r = _episodeRequest(e);
    lastRequest = r;
    return r;
  }

  Future<List<Episode>> episodes(Item item) async {
    final sid = item.seriesId;
    if (sid == null) return [];
    final idx = sources.indexWhere((s) => s.id == item.sourceId);
    if (idx < 0) return [];
    try {
      return await XtreamClient(sources[idx]).episodes(sid);
    } catch (_) {
      return [];
    }
  }

  // ---------- Resume ----------

  List<double>? getResume(String id) => _resume[id];

  double? resumeFraction(String id) {
    final r = _resume[id];
    if (r == null || r.length != 2 || r[1] <= 0) return null;
    return (r[0] / r[1]).clamp(0.0, 1.0);
  }

  void saveResume(String id, double seconds, double duration) {
    if (duration <= 120 || seconds < 20) return;
    if (seconds / duration > 0.95) {
      _resume.remove(id);
    } else {
      _resume[id] = [seconds, duration];
    }
    prefs.setString('resume', jsonEncode(_resume));
  }

  void clearResume(String id) {
    if (_resume.remove(id) != null) {
      prefs.setString('resume', jsonEncode(_resume));
    }
  }
}

final AppStore store = AppStore();
