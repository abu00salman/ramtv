import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'm3u.dart';
import 'paths.dart';
import 'text_utils.dart';
import 'epg.dart';

String _encodeItems(List<Item> l) =>
    jsonEncode(l.map((e) => e.toJson()).toList());

List<T> _decodeSavedList<T>(
    String? text, T Function(Map<String, dynamic>) decode) {
  if (text == null) return [];
  try {
    final data = jsonDecode(text);
    if (data is! List) return [];
    final out = <T>[];
    for (final row in data) {
      try {
        if (row is Map) out.add(decode(Map<String, dynamic>.from(row)));
      } catch (_) {
        // One corrupt entry must not prevent startup or hide valid entries.
      }
    }
    return out;
  } catch (_) {
    return [];
  }
}

List<Item> _decodeItems(String s) => _decodeSavedList(s, Item.fromJson);

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
  AppStore({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  final EpgCache _epgCache = EpgCache();

  Future<List<EpgProgram>> epg(Item item, {required http.Client client}) async {
    if (item.kind != Kind.live) return [];
    final index = sources.indexWhere((s) => s.id == item.sourceId);
    if (index < 0 || sources[index].type != 'xtream') return [];
    final key = '${item.sourceId}|${item.id}';
    final cached = _epgCache.get(key);
    if (cached != null) return cached;
    final path = Uri.tryParse(item.url ?? '')?.pathSegments;
    if (path == null || path.isEmpty) return [];
    final streamId = path.last.split('.').first;
    if (int.tryParse(streamId) == null) return [];
    final response = await XtreamClient(sources[index], client: client)
        .call('get_short_epg', {'stream_id': streamId, 'limit': '6'});
    final programs = parseXtreamEpg(response);
    _epgCache.put(key, programs);
    return programs;
  }

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
  int _refreshGeneration = 0;
  http.Client? _refreshClient;
  Future<void> _cacheWrite = Future<void>.value();

  @override
  void dispose() {
    ++_refreshGeneration;
    _refreshClient?.close();
    super.dispose();
  }

  List<Item> queue = [];
  int queueIndex = 0;
  List<Episode> epQueue = [];
  int epIndex = 0;
  String epSeries = '';
  PlayRequest? lastRequest;

  late SharedPreferences prefs;
  Map<String, List<double>> _resume = {};

  // ---------- Source view / status / kids mode ----------

  List<Item> _raw = [];
  String? activeSourceId;
  bool kidsMode = false;

  /// Result of the last refresh per source id (true = refreshed fine). No URLs or credentials.
  final Map<String, bool> sourceRefreshOk = {};
  DateTime? lastRefreshAt;
  bool? internetOk;
  final Map<String, bool> sourceReachable = {};
  DateTime? lastCheckAt;
  bool? streamOk;
  DateTime? streamAt;
  bool checking = false;

  void _loadView() {
    activeSourceId = prefs.getString('activeSource');
    kidsMode = prefs.getBool('kids.mode') ?? false;
    final last = prefs.getInt('lastRefresh');
    if (last != null) lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(last);
  }

  Source? get activeSource {
    for (final s in sources) {
      if (s.id == activeSourceId) return s;
    }
    return sources.isNotEmpty ? sources.first : null;
  }

  void setActiveSource(String? id) {
    activeSourceId = id;
    if (id == null) {
      prefs.remove('activeSource');
    } else {
      prefs.setString('activeSource', id);
    }
    _applyView();
    notifyListeners();
  }

  bool get hasPin => (prefs.getString('kids.pin') ?? '').isNotEmpty;
  bool checkPin(String pin) => pin == (prefs.getString('kids.pin') ?? '');
  void setPin(String pin) => prefs.setString('kids.pin', pin);

  void setKidsMode(bool on) {
    kidsMode = on;
    prefs.setBool('kids.mode', on);
    _applyView();
    notifyListeners();
  }

  static final RegExp _kidsGood = RegExp(
      r'kid|cartoon|children|child|family|junior|baby|disney|nick|toon|أطفال|طفل|كرتون|عائل|بيبي|سبيستون|كراميش|طيور الجنة',
      caseSensitive: false);
  static final RegExp _kidsBad =
      RegExp(r'xxx|adult|porn|18\+|erotic|sex', caseSensitive: false);

  bool _kidsSafe(Item i) {
    final text = '${i.group} ${i.name}';
    return _kidsGood.hasMatch(text) && !_kidsBad.hasMatch(text);
  }

  void reportStream(bool ok) {
    if (streamOk == ok && streamAt != null &&
        DateTime.now().difference(streamAt!).inSeconds < 20) {
      return;
    }
    streamOk = ok;
    streamAt = DateTime.now();
    notifyListeners();
  }

  /// Checks internet reachability and each source with light requests (no catalogue download).
  Future<void> checkConnection() async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      try {
        final r = await InternetAddress.lookup('example.com')
            .timeout(const Duration(seconds: 4));
        internetOk = r.isNotEmpty;
      } catch (_) {
        internetOk = false;
      }
      sourceReachable.clear();
      for (final s in List<Source>.of(sources)) {
        if (s.type == 'demo') {
          sourceReachable[s.id] = internetOk ?? false;
          continue;
        }
        final c = _clientFactory();
        try {
          if (s.type == 'xtream') {
            final res = await XtreamClient(s, client: c).call();
            sourceReachable[s.id] = res is Map && res['user_info'] is Map;
          } else {
            final req = http.Request('GET', Uri.parse(s.url.trim()));
            final res = await c.send(req).timeout(const Duration(seconds: 8));
            await res.stream.listen((_) {}).cancel();
            sourceReachable[s.id] = res.statusCode < 400;
          }
        } catch (_) {
          sourceReachable[s.id] = false;
        } finally {
          c.close();
        }
      }
      lastCheckAt = DateTime.now();
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    sources = _decodeSavedList(prefs.getString('sources'), Source.fromJson);
    _loadView();
    favorites = (prefs.getStringList('favorites') ?? <String>[]).toSet();
    recents = _decodeSavedList(prefs.getString('recents'), Item.fromJson);
    final rs = prefs.getString('resume');
    if (rs != null) {
      try {
        final m = jsonDecode(rs);
        if (m is Map) {
          for (final entry in m.entries) {
            final value = entry.value;
            if (entry.key is String &&
                value is List &&
                value.length == 2 &&
                value.every((x) => x is num && x.isFinite && x >= 0)) {
              _resume[entry.key as String] =
                  value.map((x) => (x as num).toDouble()).toList();
            }
          }
        }
      } catch (_) {}
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
    if (items.isEmpty ||
        age > 6 * 3600 * 1000 ||
        (prefs.getInt('dataVersion') ?? 0) != 3) {
      await refresh();
    }
  }

  // ---------- Sources ----------

  void _saveSources() {
    prefs.setString(
        'sources', jsonEncode(sources.map((e) => e.toJson()).toList()));
  }

  void addSource(Source s) {
    sources.add(s);
    _saveSources();
    notifyListeners();
    refresh();
  }

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  void addDemo() =>
      addSource(Source(id: newId(), name: 'Demo', type: 'demo', url: ''));

  void removeSource(String id) {
    sources.removeWhere((e) => e.id == id);
    _saveSources();
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    _refreshClient?.close();
    final client = _clientFactory();
    _refreshClient = client;
    final currentSources = List<Source>.of(sources);
    if (sources.isEmpty) {
      _setItems([]);
      loading = false;
      error = null;
      unawaited(_saveCache([]));
      client.close();
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final all = <Item>[];
    try {
      for (final s in currentSources) {
        try {
          if (s.type == 'm3u') {
            all.addAll(await loadM3U(s, client: client));
          } else if (s.type == 'xtream') {
            all.addAll(await XtreamClient(s, client: client).fetchAll(s.id));
          } else {
            all.addAll(demoItems(s.id));
          }
          sourceRefreshOk[s.id] = true;
        } catch (_) {
          if (generation != _refreshGeneration) return;
          sourceRefreshOk[s.id] = false;
          error =
              '${s.name}: Unable to refresh source. Check connection and credentials.';
          // Keep the last usable catalogue for an temporarily offline provider.
          all.addAll(_raw.where((item) => item.sourceId == s.id));
        }
        if (generation != _refreshGeneration) return;
      }
      _setItems(all);
      loading = false;
      if (error == null) {
        prefs.setInt('lastRefresh', DateTime.now().millisecondsSinceEpoch);
        prefs.setInt('dataVersion', 3);
        lastRefreshAt = DateTime.now();
      }
      notifyListeners();
      unawaited(_saveCache(all));
    } finally {
      client.close();
      if (identical(_refreshClient, client)) _refreshClient = null;
    }
  }

  Future<void> _saveCache(List<Item> all) {
    final snapshot = List<Item>.of(all);
    _cacheWrite = _cacheWrite.then((_) => _writeCache(snapshot));
    return _cacheWrite;
  }

  Future<void> _writeCache(List<Item> all) async {
    try {
      final txt = await compute(_encodeItems, all);
      final f = await cacheFile('items.json');
      await f.writeAsString(txt);
    } catch (_) {}
  }

  void _setItems(List<Item> list) {
    _raw = list;
    _applyView();
  }

  void _applyView() {
    final seen = <String>{};
    final unique = <Item>[];
    for (final i in _raw) {
      if (activeSourceId != null && i.sourceId != activeSourceId) continue;
      if (kidsMode && !_kidsSafe(i)) continue;
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

  List<Item> get favoriteItems =>
      items.where((e) => favorites.contains(e.id)).toList();

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
    prefs.setString(
        'recents', jsonEncode(recents.map((e) => e.toJson()).toList()));
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

  /// Confirms a channel chosen in the in-player browser. When [list] is given it becomes the zap queue.
  PlayRequest? switchLive(Item item, {List<Item>? list}) {
    if (list != null && list.isNotEmpty) queue = list;
    final i = queue.indexWhere((e) => e.id == item.id);
    if (i >= 0) queueIndex = i;
    return _startQueued(item);
  }

  /// The live channel watched before the current one (for "previous channel").
  Item? previousLive(String? currentId) {
    for (final r in recents) {
      if (r.kind == Kind.live && r.id != currentId) return r;
    }
    return null;
  }

  PlayRequest? _startQueued(Item item) {
    final r = _request(item);
    if (r == null) return null;
    lastRequest = r;
    _touchRecents(item);
    return r;
  }

  PlayRequest _episodeRequest(Episode e) {
    final label =
        epSeries.isEmpty ? e.title : '$epSeries S${e.season}E${e.number}';
    return PlayRequest(
      title: label,
      url: e.url,
      isLive: false,
      resumeKey: 'ep|${e.id}',
      isEpisode: true,
    );
  }

  PlayRequest prepareEpisode(
      Episode e, List<Episode> list, String seriesTitle) {
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
