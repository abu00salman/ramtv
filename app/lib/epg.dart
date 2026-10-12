import 'dart:convert';

class EpgProgram {
  final String title;
  final DateTime start;
  final DateTime end;
  const EpgProgram(
      {required this.title, required this.start, required this.end});
  bool isCurrent(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}

/// Unix timestamps carry the timezone; never guess it from display strings.
List<EpgProgram> parseXtreamEpg(dynamic response) {
  if (response is! Map || response['epg_listings'] is! List) return [];
  final programs = <EpgProgram>[];
  for (final row in response['epg_listings'] as List) {
    if (row is! Map) continue;
    final start = int.tryParse('${row['start_timestamp']}');
    final end =
        int.tryParse('${row['stop_timestamp'] ?? row['end_timestamp']}');
    if (start == null || end == null || end <= start) continue;
    var title = '${row['title'] ?? ''}'.trim();
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(title)));
      if (decoded.isNotEmpty) title = decoded;
    } on FormatException {
      // Compatible providers may return plain UTF-8 titles.
    }
    if (title.isEmpty) continue;
    programs.add(EpgProgram(
      title: title,
      start: DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(end * 1000, isUtc: true),
    ));
  }
  programs.sort((a, b) => a.start.compareTo(b.start));
  return programs;
}

class EpgCache {
  final int capacity;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, (DateTime, List<EpgProgram>)> _entries = {};
  EpgCache(
      {this.capacity = 128,
      this.ttl = const Duration(minutes: 1),
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  List<EpgProgram>? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_now().difference(entry.$1) >= ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.$2;
  }

  void put(String key, List<EpgProgram> programs) {
    if (capacity <= 0) return;
    _entries.remove(key);
    while (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = (_now(), List<EpgProgram>.unmodifiable(programs));
  }
}
