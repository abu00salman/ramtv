import 'models.dart';

class ParsedTitle {
  String title;
  String? year;
  ParsedTitle(this.title, this.year);
}

class Split {
  final String? prefix;
  final String rest;
  const Split(this.prefix, this.rest);
}

class LiveName {
  static Split prefixSplit(String s) {
    for (final sep in [':', '|']) {
      final i = s.indexOf(sep);
      if (i >= 0) {
        final p = s.substring(0, i).trim();
        final rest = s.substring(i + 1).trim();
        if (p.isNotEmpty && rest.isNotEmpty && p.length <= 24) {
          return Split(p, rest);
        }
      }
    }
    return Split(null, s);
  }

  static String clean(String s) {
    var t = prefixSplit(s).rest;
    // "(1080)", "(720p)", "(HEVC)", "()" are noise in a channel name.
    t = t.replaceAll(
        RegExp(r'\(\s*(?:\d{3,4}p?|4k|fhd|uhd|hd|sd|hevc|h265)?\s*\)', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\b(4k|uhd|fhd|hd|sd|hevc|h265)\b', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? s : t;
  }
}

class TitleCleaner {
  static ParsedTitle parse(String raw) {
    var s = raw;
    String? year;
    final y1 = RegExp(r'\((19|20)\d{2}\)').firstMatch(s);
    if (y1 != null) {
      year = y1.group(0)!.substring(1, 5);
      s = s.replaceRange(y1.start, y1.end, ' ');
    } else {
      final y2 = RegExp(r'\b(19|20)\d{2}\s*$').firstMatch(s);
      if (y2 != null) {
        final rest = s.substring(0, y2.start).trim();
        if (rest.isNotEmpty) {
          year = y2.group(0)!.trim();
          s = rest;
        }
      }
    }
    s = s.replaceAll(RegExp(r'\[.*?\]|\(.*?\)'), ' ');
    s = s.replaceAll(RegExp(r'\bS\d{1,4}\s*E\d+.*$', caseSensitive: false), ' ');
    s = s.replaceFirst(RegExp(r'^\s*[A-Za-z]{2,3}\s*[|:]\s*'), '');
    s = s.replaceAll(RegExp(r'[._]'), ' ');
    s = s.replaceAll(
        RegExp(
            r'\b(4k|8k|uhd|fhd|hd|1080p|720p|2160p|bluray|blu-ray|web-?dl|webrip|hdrip|x264|x265|h264|h265|hevc|hdr|dolby|atmos|dubbed|multi|sub|subbed)\b',
            caseSensitive: false),
        ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[\s\-_.:|]+|[\s\-_.:|]+$'), '');
    return ParsedTitle(s, year);
  }

  static String normalize(String raw) {
    var t = raw.toLowerCase();
    t = t.replaceFirst(RegExp(r'^\s*[\[\(|]*[a-z]{2,3}[\]\)|]*\s*[|:\-]\s*'), '');
    t = t.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
    t = t.replaceAll(
        RegExp(r'\b(hd|fhd|uhd|sd|4k|8k|hevc|h265|h264|1080p|720p|hq|backup|raw|tv|channel)\b'), ' ');
    t = t.replaceAll('sports', 'sport');
    t = t.replaceAllMapped(RegExp(r'\b0+(\d)'), (m) => m.group(1)!);
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    return t;
  }
}

extension ItemDisplay on Item {
  String get displayTitle {
    if (kind == Kind.live) return LiveName.clean(name);
    final t = TitleCleaner.parse(name).title;
    return t.isEmpty ? name : t;
  }

  String? get year => kind == Kind.live ? null : TitleCleaner.parse(name).year;

  List<String> get badges {
    final n = name.toLowerCase();
    bool has(String p) => RegExp('\\b($p)\\b').hasMatch(n);
    final out = <String>[];
    if (has('4k|uhd')) {
      out.add('4K');
    } else if (has('fhd')) {
      out.add('FHD');
    } else if (has('hd')) {
      out.add('HD');
    }
    if (has('hevc|h265')) out.add('HEVC');
    return out;
  }
}

final RegExp _arDiacritics = RegExp('[\u064B-\u065F\u0670\u0640]');
final RegExp _arAlef = RegExp('[\u0623\u0625\u0622\u0671]');
final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Case-insensitive search key that ignores Arabic diacritics and common letter variants
/// (alef forms, ya/alef-maqsura, ta-marbuta) so "أطفال" and "اطفال" match.
String normalizeSearch(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(_arDiacritics, '');
  t = t.replaceAll(_arAlef, '\u0627');
  t = t.replaceAll('\u0649', '\u064A').replaceAll('\u0629', '\u0647');
  t = t.replaceAll('\u0624', '\u0648').replaceAll('\u0626', '\u064A');
  return t.replaceAll(_nonWord, ' ').trim();
}

final Expando<String> _searchKeys = Expando<String>();

/// Normalized "name + group" for an item, computed once per item.
String searchKey(Item i) => _searchKeys[i] ??= normalizeSearch('${i.name} ${i.group}');
