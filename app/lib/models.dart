enum Kind { live, movie, series }

class Source {
  final String id;
  final String name;
  final String type; // m3u | xtream | demo
  final String url;
  final String username;
  final String password;

  const Source({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
    this.username = '',
    this.password = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'url': url,
        'username': username,
        'password': password,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        url: j['url'] as String,
        username: (j['username'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
      );
}

class Item {
  final String id;
  final String name;
  final String? logo;
  String group;
  final String? url;
  final Kind kind;
  final String? seriesId;
  final String sourceId;

  Item({
    required this.id,
    required this.name,
    this.logo,
    required this.group,
    this.url,
    required this.kind,
    this.seriesId,
    required this.sourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'l': logo,
        'g': group,
        'u': url,
        'k': kind.index,
        's': seriesId,
        'src': sourceId,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['n'] as String,
        logo: j['l'] as String?,
        group: j['g'] as String,
        url: j['u'] as String?,
        kind: Kind.values[j['k'] as int],
        seriesId: j['s'] as String?,
        sourceId: j['src'] as String,
      );
}

class Episode {
  final String id;
  final String title;
  final String url;
  final int season;
  final int number;

  const Episode({
    required this.id,
    required this.title,
    required this.url,
    required this.season,
    required this.number,
  });
}
