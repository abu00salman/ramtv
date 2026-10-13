import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../artwork.dart';
import '../models.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';
import 'screens.dart';
import 'widgets.dart';

const Color kTvBg = Color(0xFF070B14);
const Color kTvPanel = Color(0xFF0A1020);
const Color kTvLive = Color(0xFFE5233C);

/// 1.0 at 540dp screen height. Keeps the layout proportional on any TV density.
double tvScale(BuildContext c) =>
    (MediaQuery.of(c).size.height / 540).clamp(0.85, 2.2).toDouble();

bool _keyboardNavigation() =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

String _fmtDuration(double seconds) {
  final d = Duration(seconds: seconds.round());
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// ---------------------------------------------------------------- Focus primitive

/// Focusable element with a clear white frame (plus a small blue glow) for remote navigation.
/// After the tap callback finishes (e.g. a player route is closed) focus returns to this element.
class TvFocusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final TapCb? onTap;
  final double radius;
  final bool autofocus;
  final FocusNode? focusNode;

  const TvFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.radius = 14,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node;
  late final bool _ownsNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final r = widget.onTap?.call();
    if (r is Future) await r;
    if (mounted && _keyboardNavigation()) _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: InkWell(
        focusNode: _node,
        autofocus: widget.autofocus,
        borderRadius: r,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        onTap: widget.onTap == null ? null : _activate,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            Scrollable.ensureVisible(context,
                duration: const Duration(milliseconds: 150), alignment: 0.5);
          }
        },
        child: AnimatedScale(
          scale: _focused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              boxShadow: _focused
                  ? [BoxShadow(color: kBrand.withValues(alpha: 0.55), blurRadius: 14)]
                  : null,
            ),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: r,
                border: Border.all(
                    color: _focused ? Colors.white : Colors.transparent, width: 3),
              ),
              child: widget.builder(context, _focused),
            ),
          ),
        ),
      ),
    );
  }
}

class TvButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final bool autofocus;
  final TapCb onTap;

  const TvButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = tvScale(context);
    return TvFocusable(
      autofocus: autofocus,
      radius: 12 * s,
      onTap: onTap,
      builder: (ctx, focused) => Container(
        padding: EdgeInsets.symmetric(horizontal: 26 * s, vertical: 12 * s),
        decoration: BoxDecoration(
          color: filled ? kBrand : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12 * s),
          border: filled ? null : Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 26 * s, color: Colors.white),
              SizedBox(width: 10 * s),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 21 * s, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Shell

class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  int _index = 0;
  bool _sideFocused = false;
  final List<FocusNode> _navNodes = List<FocusNode>.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final n in _navNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Widget _page() {
    switch (_index) {
      case 0:
        return const TvHome();
      case 1:
        return const LiveScreen();
      case 2:
        return const LibraryScreen(key: ValueKey('tv-movies'), fixedTab: 0);
      case 3:
        return const LibraryScreen(key: ValueKey('tv-series'), fixedTab: 1);
      case 4:
        return const FavoritesScreen();
      default:
        return const SettingsScreen();
    }
  }

  void _onBack() {
    if (_sideFocused) {
      if (_index != 0) {
        setState(() => _index = 0);
        _navNodes[0].requestFocus();
      } else {
        SystemNavigator.pop();
      }
    } else {
      _navNodes[_index].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The sidebar is the first child: it sits on the right in Arabic (RTL) and on the left in English.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: kTvBg,
        body: Row(
          children: [
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (f) => _sideFocused = f,
              child: _TvSidebar(
                index: _index,
                nodes: _navNodes,
                onSelect: (i) => setState(() => _index = i),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  _page(),
                  ListenableBuilder(
                    listenable: store,
                    builder: (context, _) => store.loading
                        ? const Align(
                            alignment: Alignment.topCenter,
                            child: LinearProgressIndicator(minHeight: 3))
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSidebar extends StatelessWidget {
  final int index;
  final List<FocusNode> nodes;
  final ValueChanged<int> onSelect;
  const _TvSidebar({required this.index, required this.nodes, required this.onSelect});

  static const List<IconData> _icons = [
    Icons.home_rounded,
    Icons.desktop_windows_rounded,
    Icons.movie_filter_rounded,
    Icons.theaters_rounded,
    Icons.favorite_border_rounded,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final s = tvScale(context);
    final width = MediaQuery.of(context).size.width * 0.19;
    final labels = [
      t('Home'),
      t('Channels'),
      t('Movies'),
      t('Series'),
      t('Favorites'),
      t('Settings'),
    ];
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: kTvPanel,
        border: BorderDirectional(end: BorderSide(color: Color(0xFF16203A))),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 18 * s),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 22 * s),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10 * s),
                    child: Image.asset('assets/icon.png',
                        width: 38 * s, height: 38 * s, cacheWidth: 128),
                  ),
                  SizedBox(width: 10 * s),
                  Text('RaM tv',
                      style: TextStyle(
                          fontSize: 26 * s, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
            ),
            for (var i = 0; i < 6; i++)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 3 * s),
                child: TvFocusable(
                  focusNode: nodes[i],
                  radius: 14 * s,
                  onTap: () => onSelect(i),
                  builder: (ctx, focused) {
                    final selected = i == index;
                    return Container(
                      height: 50 * s,
                      padding: EdgeInsets.symmetric(horizontal: 16 * s),
                      decoration: BoxDecoration(
                        color: selected
                            ? kBrand
                            : (focused
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(14 * s),
                      ),
                      child: Row(
                        children: [
                          Icon(_icons[i],
                              size: 26 * s, color: selected ? Colors.white : Colors.white70),
                          SizedBox(width: 14 * s),
                          Expanded(
                            child: Text(labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 20 * s,
                                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                    color: selected ? Colors.white : Colors.white70)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const Spacer(),
            Divider(color: const Color(0xFF16203A), height: 24 * s),
            ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final ok = store.sources.isNotEmpty && store.error == null;
                final label =
                    store.loading ? t('Updating') : (ok ? t('Connected') : t('Offline'));
                final color = store.loading
                    ? Colors.amber
                    : (ok ? const Color(0xFF22C55E) : Colors.redAccent);
                return Column(
                  children: [
                    _Avatar(size: 52 * s, dot: color),
                    SizedBox(height: 8 * s),
                    Text(label,
                        style: TextStyle(fontSize: 16 * s, color: Colors.white70)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final double size;
  final Color dot;
  const _Avatar({required this.size, required this.dot});

  @override
  Widget build(BuildContext context) {
    final name = store.sources.isNotEmpty ? store.sources.first.name.trim() : '';
    final initial = name.isEmpty ? 'R' : name.substring(0, 1).toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF16203A),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(initial,
                style: TextStyle(
                    fontSize: size * 0.42, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: kTvPanel, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Home

class TvHome extends StatefulWidget {
  const TvHome({super.key});

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _ChannelSet {
  final String title;
  final List<Item> items;
  const _ChannelSet(this.title, this.items);
}

class _TvHomeState extends State<TvHome> {
  Timer? _clock;
  String _time = '';

  static String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _time = _now();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      final v = _now();
      if (mounted && v != _time) setState(() => _time = v);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Item? _pickHero() {
    for (final r in store.recents) {
      if (r.kind != Kind.live) return r;
    }
    final pool = store.movies.isNotEmpty
        ? store.movies
        : (store.series.isNotEmpty ? store.series : store.live);
    if (pool.isEmpty) return null;
    final day = DateTime.now().difference(DateTime(2026)).inDays.abs();
    final span = pool.length < 40 ? pool.length : 40;
    return pool[day % span];
  }

  _ChannelSet _channels() {
    final favs = store.favoriteItems.where((e) => e.kind == Kind.live).toList();
    if (favs.isNotEmpty) return _ChannelSet(t('Your favorite channels'), favs.take(14).toList());
    final rec = store.recents.where((e) => e.kind == Kind.live).toList();
    if (rec.isNotEmpty) return _ChannelSet(t('Recent Channels'), rec);
    return _ChannelSet(t('Channels'), store.live.take(14).toList());
  }

  @override
  Widget build(BuildContext context) {
    final s = tvScale(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.sources.isEmpty) {
            return const SingleChildScrollView(child: EmptyState());
          }
          final hero = _pickHero();
          final cont = store.recents.where((e) => e.kind != Kind.live).take(8).toList();
          final ch = _channels();
          return ListView(
            padding: EdgeInsets.only(bottom: 24 * s),
            children: [
              _HeroSection(item: hero, time: _time, s: s),
              if (cont.isNotEmpty) ...[
                _SectionTitle(t('Continue Watching'), s),
                SizedBox(
                  height: 190 * s,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 36 * s, vertical: 10 * s),
                    itemCount: cont.length,
                    separatorBuilder: (_, __) => SizedBox(width: 18 * s),
                    itemBuilder: (_, i) => _ContinueCard(item: cont[i], s: s),
                  ),
                ),
              ],
              if (ch.items.isNotEmpty) ...[
                _SectionTitle(ch.title, s),
                SizedBox(
                  height: 140 * s,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 36 * s, vertical: 10 * s),
                    itemCount: ch.items.length,
                    separatorBuilder: (_, __) => SizedBox(width: 16 * s),
                    itemBuilder: (_, i) => _ChannelCard(item: ch.items[i], list: ch.items, s: s),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final double s;
  const _SectionTitle(this.text, this.s);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 40 * s, top: 14 * s),
      child: Text(text,
          style: TextStyle(fontSize: 26 * s, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

class _HeroSection extends StatefulWidget {
  final Item? item;
  final String time;
  final double s;
  const _HeroSection({required this.item, required this.time, required this.s});

  @override
  State<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<_HeroSection> {
  ArtMeta? _meta;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_HeroSection old) {
    super.didUpdateWidget(old);
    if (old.item?.id != widget.item?.id) {
      _meta = null;
      _load();
    }
  }

  Future<void> _load() async {
    final it = widget.item;
    if (it == null) return;
    final m = await ArtworkService.instance.meta(it);
    if (mounted && widget.item?.id == it.id) setState(() => _meta = m);
  }

  String _subtitle(Item it) {
    final o = (_meta?.overview ?? '').trim();
    if (o.isNotEmpty) {
      final cut = o.length > 150 ? '${o.substring(0, 150).trimRight()}…' : o;
      return cut;
    }
    return it.group == 'Other' || it.group == 'Demo' ? '' : it.group;
  }

  String _metaLine(Item it) {
    final parts = <String>[];
    final y = it.year;
    if (y != null) parts.add(y);
    parts.addAll(it.badges);
    parts.add(it.kind == Kind.live
        ? t('Live')
        : (it.kind == Kind.movie ? t('Movies') : t('Series')));
    return parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final it = widget.item;
    final h = MediaQuery.of(context).size.height * 0.52;
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF0B1224)),
          if (it != null && _meta?.backdropPath != null)
            Image.network(
              'https://image.tmdb.org/t/p/w1280${_meta!.backdropPath}',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 1280,
              errorBuilder: (c, e, st) => const SizedBox.shrink(),
            )
          else if (it != null)
            PositionedDirectional(
              end: 60 * s,
              top: 76 * s,
              bottom: 24 * s,
              child: AspectRatio(
                aspectRatio: it.kind == Kind.live ? 1.6 : 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16 * s),
                  child: ArtThumb(item: it, fit: it.kind == Kind.live, cacheWidth: 600),
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [Color(0xE60A1020), Color(0x000A1020)],
                stops: [0.0, 0.75],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Color(0x00070B14), Color(0xFF070B14)],
              ),
            ),
          ),
          // top bar: search pill (start) and clock + avatar (end)
          PositionedDirectional(
            top: 18 * s,
            start: 40 * s,
            end: 40 * s,
            child: Row(
              children: [
                TvFocusable(
                  radius: 26 * s,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const SearchPage())),
                  builder: (c, f) => Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 22 * s, vertical: 10 * s),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(26 * s),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, size: 24 * s, color: Colors.white),
                        SizedBox(width: 10 * s),
                        Text(t('Search'),
                            style: TextStyle(fontSize: 18 * s, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(widget.time,
                    style: TextStyle(
                        fontSize: 20 * s, fontWeight: FontWeight.w600, color: Colors.white)),
                SizedBox(width: 14 * s),
                ListenableBuilder(
                  listenable: store,
                  builder: (c, _) => _Avatar(
                      size: 40 * s,
                      dot: store.error == null ? const Color(0xFF22C55E) : Colors.redAccent),
                ),
              ],
            ),
          ),
          if (it != null)
            PositionedDirectional(
              start: 40 * s,
              bottom: 22 * s,
              width: MediaQuery.of(context).size.width * 0.42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 46 * s,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if (_subtitle(it).isNotEmpty) ...[
                    SizedBox(height: 8 * s),
                    Text(_subtitle(it),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20 * s, color: Colors.white70)),
                  ],
                  SizedBox(height: 8 * s),
                  Text(_metaLine(it),
                      style: TextStyle(fontSize: 17 * s, color: Colors.white60)),
                  SizedBox(height: 14 * s),
                  Row(
                    children: [
                      TvButton(
                        label: t('Watch Now'),
                        icon: Icons.play_arrow_rounded,
                        filled: true,
                        autofocus: true,
                        onTap: () => openItem(context, it),
                      ),
                      SizedBox(width: 14 * s),
                      TvButton(
                        label: t('Details'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ItemDetailsScreen(item: it))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Cards

/// Landscape image: TMDB backdrop for movies/series when available, otherwise the normal artwork.
class _TvBackdrop extends StatefulWidget {
  final Item item;
  const _TvBackdrop({required this.item});

  @override
  State<_TvBackdrop> createState() => _TvBackdropState();
}

class _TvBackdropState extends State<_TvBackdrop> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TvBackdrop old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _path = null;
      _load();
    }
  }

  Future<void> _load() async {
    final it = widget.item;
    final m = await ArtworkService.instance.meta(it);
    if (mounted && widget.item.id == it.id && m?.backdropPath != null) {
      setState(() => _path = m!.backdropPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    if (p != null) {
      return Image.network(
        'https://image.tmdb.org/t/p/w500$p',
        fit: BoxFit.cover,
        cacheWidth: 520,
        errorBuilder: (c, e, st) => ArtThumb(item: widget.item),
      );
    }
    return ArtThumb(item: widget.item, fit: widget.item.kind == Kind.live);
  }
}

class _ContinueCard extends StatelessWidget {
  final Item item;
  final double s;
  const _ContinueCard({required this.item, required this.s});

  @override
  Widget build(BuildContext context) {
    final r = store.getResume(item.id);
    final frac = store.resumeFraction(item.id);
    return TvFocusable(
      radius: 16 * s,
      onTap: () => openItem(context, item),
      builder: (c, f) => SizedBox(
        width: 300 * s,
        height: 168 * s,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16 * s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TvBackdrop(item: item),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xEE000000)],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 14 * s,
                end: 14 * s,
                bottom: 14 * s,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 19 * s, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (r != null && r.length == 2)
                      Text('${_fmtDuration(r[0])} / ${_fmtDuration(r[1])}',
                          style: TextStyle(fontSize: 14 * s, color: Colors.white70)),
                  ],
                ),
              ),
              if (frac != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 4 * s,
                    backgroundColor: Colors.white24,
                    color: kBrand,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final Item item;
  final List<Item> list;
  final double s;
  const _ChannelCard({required this.item, required this.list, required this.s});

  @override
  Widget build(BuildContext context) {
    final live = item.kind == Kind.live;
    return TvFocusable(
      radius: 16 * s,
      onTap: () => openItem(context, item, list: live ? list : null),
      builder: (c, f) => SizedBox(
        width: 190 * s,
        height: 108 * s,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16 * s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF16203A), Color(0xFF0A1020)],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12 * s, 10 * s, 12 * s, 30 * s),
                child: ArtThumb(item: item, fit: true),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
              if (live)
                PositionedDirectional(
                  top: 8 * s,
                  end: 8 * s,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                    decoration: BoxDecoration(
                      color: kTvLive,
                      borderRadius: BorderRadius.circular(6 * s),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7 * s,
                          height: 7 * s,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                        ),
                        SizedBox(width: 5 * s),
                        Text('LIVE',
                            style: TextStyle(
                                fontSize: 12 * s,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              PositionedDirectional(
                start: 10 * s,
                end: 10 * s,
                bottom: 8 * s,
                child: Text(item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17 * s, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Favorites

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = tvScale(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final favs = store.favoriteItems;
          final channels = favs.where((e) => e.kind == Kind.live).toList();
          final others = favs.where((e) => e.kind != Kind.live).toList();
          if (favs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(40 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border_rounded, size: 64 * s, color: Colors.white38),
                    SizedBox(height: 14 * s),
                    Text(t('No favorites yet'),
                        style: TextStyle(
                            fontSize: 30 * s, fontWeight: FontWeight.w700, color: Colors.white)),
                    SizedBox(height: 8 * s),
                    Text(
                        t('Add favorites with the heart button on any channel, movie or series.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18 * s, color: Colors.white60)),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.only(bottom: 24 * s, top: 10 * s),
            children: [
              if (channels.isNotEmpty) ...[
                _SectionTitle(t('Channels'), s),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(36 * s, 12 * s, 36 * s, 8 * s),
                  child: Wrap(
                    spacing: 16 * s,
                    runSpacing: 16 * s,
                    children: [
                      for (final c in channels) _ChannelCard(item: c, list: channels, s: s),
                    ],
                  ),
                ),
              ],
              if (others.isNotEmpty) ...[
                _SectionTitle('${t('Movies')} / ${t('Series')}', s),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(36 * s, 12 * s, 36 * s, 8 * s),
                  child: Wrap(
                    spacing: 16 * s,
                    runSpacing: 16 * s,
                    children: [
                      for (final o in others)
                        PosterCard(
                          item: o,
                          width: 132 * s,
                          onTap: () => openItem(context, o),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Details

class ItemDetailsScreen extends StatefulWidget {
  final Item item;
  const ItemDetailsScreen({super.key, required this.item});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  ArtMeta? _meta;

  @override
  void initState() {
    super.initState();
    ArtworkService.instance.meta(widget.item).then((m) {
      if (mounted) setState(() => _meta = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = tvScale(context);
    final it = widget.item;
    final overview = (_meta?.overview ?? '').trim();
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: kTvBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_meta?.backdropPath != null)
              Image.network(
                'https://image.tmdb.org/t/p/w1280${_meta!.backdropPath}',
                fit: BoxFit.cover,
                cacheWidth: 1280,
                errorBuilder: (c, e, st) => const SizedBox.shrink(),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [Color(0xF0070B14), Color(0x33070B14)],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(56 * s, 40 * s, 56 * s, 40 * s),
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.displayTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 44 * s, fontWeight: FontWeight.w800, color: Colors.white)),
                      SizedBox(height: 10 * s),
                      BadgeRow(item: it),
                      if (overview.isNotEmpty) ...[
                        SizedBox(height: 14 * s),
                        Text(overview,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 20 * s, height: 1.4, color: Colors.white70)),
                      ],
                      SizedBox(height: 20 * s),
                      Row(
                        children: [
                          TvButton(
                            label: t('Watch Now'),
                            icon: Icons.play_arrow_rounded,
                            filled: true,
                            autofocus: true,
                            onTap: () => openItem(context, it),
                          ),
                          SizedBox(width: 14 * s),
                          ListenableBuilder(
                            listenable: store,
                            builder: (c, _) => TvButton(
                              label: t('Favorites'),
                              icon: store.isFavorite(it)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              onTap: () => store.toggleFavorite(it),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
