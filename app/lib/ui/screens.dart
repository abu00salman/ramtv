import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../artwork.dart';
import '../models.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';
import '../lan_add.dart';
import 'dpad.dart';
import 'player.dart';
import 'tv.dart';
import 'widgets.dart';

Future<void> openItem(BuildContext context, Item item, {List<Item>? list}) async {
  if (item.seriesId != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(item: item)));
    return;
  }
  final req = store.prepare(item, list: list);
  if (req != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(req: req)));
  }
}

/// Search as a full page (opened from the TV home search pill).
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Search'))),
      body: const SearchScreen(),
    );
  }
}

// ---------------------------------------------------------------- Root

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    store.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) return const TvShell();
    final pages = const [
      HomeScreen(),
      LiveScreen(),
      LibraryScreen(),
      SearchScreen(),
      SettingsScreen(),
    ];
    final labels = [t('Home'), t('Live'), t('Library'), t('Search'), t('Settings')];
    const icons = [
      Icons.home_rounded,
      Icons.sensors_rounded,
      Icons.video_library_rounded,
      Icons.search_rounded,
      Icons.settings_rounded,
    ];
    final body = Stack(
      children: [
        IndexedStack(index: _index, children: pages),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.loading
              ? const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator(minHeight: 3))
              : const SizedBox.shrink(),
        ),
      ],
    );
    if (isWide(context)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: const Color(0xFF0B0B0B),
              destinations: [
                for (var i = 0; i < 5; i++)
                  NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i])),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < 5; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Home

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [kBrand, Color(0xFF081A96)],
                    ),
                  ),
                  child: const Icon(Icons.live_tv_rounded, size: 56, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(t('Welcome to RaM tv'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  t('Add your own M3U playlist or server login to start watching. RaM tv is a player only and includes no channels or content.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  autofocus: true,
                  onPressed: () => showAddSource(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 6),
                    child: Text(t('Add Source')),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: store.addDemo, child: Text(t('Try Demo'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.sources.isEmpty) return const SingleChildScrollView(child: EmptyState());
        final hero = store.heroItem;
        void open(Item i) => openItem(context, i);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (hero != null) HeroBanner(item: hero, onPlay: () => open(hero)),
            const SizedBox(height: 18),
            Shelf(
                title: t('Continue Watching'),
                items: store.recents.where((e) => e.kind != Kind.live).toList(),
                onOpen: open),
            Shelf(
                title: t('Recent Channels'),
                items: store.recents.where((e) => e.kind == Kind.live).toList(),
                onOpen: open),
            Shelf(
                title: t('Favorites'),
                items: store.favorites.isEmpty ? <Item>[] : store.favoriteItems,
                onOpen: open),
            Shelf(title: t('Movies'), items: store.movies.take(24).toList(), onOpen: open),
            Shelf(title: t('Series'), items: store.series.take(24).toList(), onOpen: open),
            for (final g in store.liveGroups.take(5))
              Shelf(
                title: g,
                items: store.live.where((e) => e.group == g).take(20).toList(),
                onOpen: open,
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Live

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  String? _group;
  bool _favOnly = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        List<Item> list;
        if (_favOnly) {
          list = store.live.where((e) => store.favorites.contains(e.id)).toList();
        } else if (_group != null) {
          list = store.live.where((e) => e.group == _group).toList();
        } else {
          list = store.live;
        }
        final groups = store.liveGroups;
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(t('Live'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: groups.length + 2,
                  itemBuilder: (_, i) {
                    String label;
                    bool selected;
                    VoidCallback onTap;
                    if (i == 0) {
                      label = t('All');
                      selected = _group == null && !_favOnly;
                      onTap = () => setState(() {
                            _group = null;
                            _favOnly = false;
                          });
                    } else if (i == 1) {
                      label = '♥ ${t('Favorites')}';
                      selected = _favOnly;
                      onTap = () => setState(() {
                            _favOnly = true;
                            _group = null;
                          });
                    } else {
                      final g = groups[i - 2];
                      label = g;
                      selected = _group == g && !_favOnly;
                      onTap = () => setState(() {
                            _group = g;
                            _favOnly = false;
                          });
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
                    );
                  },
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(t('No channels'), style: const TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemExtent: isWide(context) ? 92 : 76,
                        itemBuilder: (_, i) => ChannelRow(
                          item: list[i],
                          onTap: () => openItem(context, list[i], list: list),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ChannelRow extends StatelessWidget {
  final Item item;
  final TapCb onTap;
  const ChannelRow({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final big = isWide(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: big ? 84 : 64,
                height: big ? 58 : 44,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ArtThumb(item: item, fit: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(item.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: big ? 19 : 16)),
                        ),
                        const SizedBox(width: 6),
                        for (final b in item.badges)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(b, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                            ),
                          ),
                      ],
                    ),
                    Text(item.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => store.toggleFavorite(item),
                icon: Icon(
                  store.isFavorite(item) ? Icons.favorite : Icons.favorite_border,
                  color: store.isFavorite(item) ? kBrand : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Library

class LibraryScreen extends StatefulWidget {
  /// 0 = movies only, 1 = series only, null = both with a switcher.
  final int? fixedTab;
  const LibraryScreen({super.key, this.fixedTab});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late int _tab = widget.fixedTab ?? 0;
  String? _group;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final source = _tab == 0 ? store.movies : store.series;
        final seen = <String>{};
        final groups = source.map((e) => e.group).where((g) => seen.add(g)).toList();
        final shown = _group == null ? source : source.where((e) => e.group == _group).toList();
        final extent = isWide(context) ? 190.0 : 150.0;
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          t(widget.fixedTab == null ? 'Library' : (widget.fixedTab == 0 ? 'Movies' : 'Series')),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.filter_list_rounded),
                      onSelected: (g) => setState(() => _group = g.isEmpty ? null : g),
                      itemBuilder: (_) => [
                        PopupMenuItem<String>(value: '', child: Text(t('All'))),
                        for (final g in groups) PopupMenuItem<String>(value: g, child: Text(g)),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.fixedTab == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(t('Movies'))),
                    ButtonSegment(value: 1, label: Text(t('Series'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() {
                    _tab = s.first;
                    _group = null;
                  }),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: extent,
                    mainAxisExtent: extent * 1.5 + 34,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) =>
                      PosterCard(item: shown[i], onTap: () => openItem(context, shown[i])),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Series detail

class SeriesDetailScreen extends StatefulWidget {
  final Item item;
  const SeriesDetailScreen({super.key, required this.item});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<Episode> _eps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    store.episodes(widget.item).then((e) {
      if (mounted) {
        setState(() {
          _eps = e;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final seasons = _eps.map((e) => e.season).toSet().toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.displayTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ArtThumb(item: widget.item),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.displayTitle,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    BadgeRow(item: widget.item),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _eps.isEmpty)
            Center(child: Text(t('No episodes'), style: const TextStyle(color: Colors.white54))),
          for (final s in seasons) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text('${t('Season')} $s',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final e in _eps.where((x) => x.season == s))
              Pressable(
                onTap: () {
                  final req = store.prepareEpisode(e, _eps, widget.item.displayTitle);
                  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(req: req)));
                },
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill_rounded, color: kBrand),
                  title: Text('${e.number}. ${e.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Search

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _c.text.trim().toLowerCase();
    final results = q.length < 2
        ? <Item>[]
        : store.items.where((e) => e.name.toLowerCase().contains(q)).take(150).toList();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DpadTextField(
              controller: _c,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: t('Search channels, movies, series'),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final item = results[i];
                return Pressable(
                  onTap: () => openItem(context, item),
                  child: ListTile(
                    leading: SizedBox(
                      width: 52,
                      height: 52,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ArtThumb(item: item, fit: item.kind == Kind.live),
                      ),
                    ),
                    title: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.group, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Settings

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tmdb;

  @override
  void initState() {
    super.initState();
    _tmdb = TextEditingController(text: store.prefs.getString('tmdbKey') ?? '');
  }

  @override
  void dispose() {
    _tmdb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t('Settings'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(t('Sources'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
            for (final s in store.sources)
              ListTile(
                title: Text(s.name),
                subtitle: Text(s.type == 'demo' ? t('Demo') : _maskUrl(s.url), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => store.removeSource(s.id),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_rounded, color: kBrand),
              title: Text(t('Add Source')),
              onTap: () => showAddSource(context),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(t('Refresh')),
              trailing: store.loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: store.refresh,
            ),
            if (store.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(store.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            Text(t('Artwork'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
            const SizedBox(height: 8),
            DpadTextField(
              controller: _tmdb,
              onChanged: (v) => store.prefs.setString('tmdbKey', v.trim()),
              decoration: const InputDecoration(
                labelText: 'TMDB API key (optional)',
                helperText: 'Free key from themoviedb.org > Settings > API. Restart the app after adding it.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_rounded),
              title: Text(t('Clear artwork cache')),
              onTap: () => ArtworkService.instance.clear(),
            ),
            const SizedBox(height: 16),
            Text(t('About'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              t('RaM tv is a player only. It does not provide or include any channels, playlists or content. Use only sources you are authorized to access.'),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            const Text('This product uses the TMDB API but is not endorsed or certified by TMDB.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 8),
            const Text('RaM tv  1.0', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

String _maskUrl(String u) => u.replaceAllMapped(
    RegExp(r'(password|pass|pwd)=([^&]+)', caseSensitive: false), (m) => '${m.group(1)}=••••');

Future<void> showAddSource(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _AddSourceDialog());
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  String _type = 'm3u';
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final LanAddServer _lan = LanAddServer();
  String? _lanUrl;
  bool _lanStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tvLike =
        defaultTargetPlatform == TargetPlatform.android && MediaQuery.of(context).size.width >= 900;
    if (tvLike && !_lanStarted) {
      _lanStarted = true;
      _lan.onAdded = () {
        if (mounted) Navigator.of(context).pop();
      };
      _lan.start().then((u) {
        if (mounted) setState(() => _lanUrl = u);
      });
    }
  }

  @override
  void dispose() {
    _lan.stop();
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _valid =>
      _url.text.trim().isNotEmpty &&
      (_type == 'm3u' || (_user.text.trim().isNotEmpty && _pass.text.isNotEmpty));

  void _save() {
    if (!_valid) return;
    final fallback = _type == 'm3u' ? 'Playlist' : 'Server';
    store.addSource(Source(
      id: store.newId(),
      name: _name.text.trim().isEmpty ? fallback : _name.text.trim(),
      type: _type,
      url: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Add Source')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_lanUrl != null) ...[
                Text(t('Add from your phone'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(6),
                      child: QrImageView(data: _lanUrl!, size: 120, backgroundColor: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_lanUrl!,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('PIN: ${_lan.pin}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            t('Scan the code or open the address in your phone browser (same Wi-Fi). Enter the PIN shown here.'),
                            style: const TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Text(t('Or type it here'), style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 8),
              ],
              Center(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'm3u', label: Text('M3U')),
                    ButtonSegment(value: 'xtream', label: Text('Xtream')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              const SizedBox(height: 12),
              DpadTextField(
                controller: _name,
                decoration: InputDecoration(labelText: t('Name')),
                textInputAction: TextInputAction.next,
              ),
              DpadTextField(
                controller: _url,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.url,
                textInputAction: _type == 'm3u' ? TextInputAction.done : TextInputAction.next,
                decoration: InputDecoration(
                    labelText: _type == 'm3u' ? t('Playlist URL') : t('Server URL')),
              ),
              if (_type == 'xtream') ...[
                DpadTextField(
                  controller: _user,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: t('Username')),
                ),
                DpadTextField(
                  controller: _pass,
                  onChanged: (_) => setState(() {}),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: t('Password')),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('Cancel'))),
        FilledButton(onPressed: _valid ? _save : null, child: Text(t('Save'))),
      ],
    );
  }
}
