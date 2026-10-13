import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../artwork.dart';
import '../models.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';
import '../device_profile.dart';
import '../theme.dart';

/// Current accent color (changes with the selected theme).
Color get kBrand => Pal.current.accent;

bool isWide(BuildContext c) =>
    DeviceProfile.isTelevision || MediaQuery.of(c).size.width >= 900;

/// Tap callback that may return a Future (e.g. a pushed route). When it does, focus is
/// restored to the tapped element once the route is closed.
typedef TapCb = Object? Function();

bool _keyboardNavigation() =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// Handles the remote's OK/Enter key: immediate tap (default), long press, or repeat while held.
/// Each physical press triggers exactly one action.
class SelectKeyHandler {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(int repeats)? onRepeat;
  SelectKeyHandler({required this.onTap, this.onLongPress, this.onRepeat});

  DateTime? _down;
  bool _fired = false;
  int _repeats = 0;

  static bool isSelect(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter;

  KeyEventResult handle(KeyEvent e) {
    if (!isSelect(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = DateTime.now();
      _fired = false;
      _repeats = 0;
      if (onLongPress == null) {
        _fired = true;
        onTap();
      }
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) {
      _repeats++;
      final held = DateTime.now().difference(_down ?? DateTime.now());
      if (onLongPress != null && !_fired && held >= const Duration(milliseconds: 550)) {
        _fired = true;
        onLongPress!();
      } else if (onRepeat != null) {
        onRepeat!(_repeats);
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      if (!_fired && onLongPress != null) onTap();
      _down = null;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// Toggles a favorite and confirms with a short message.
void toggleFavoriteWithToast(BuildContext context, Item item) {
  final was = store.isFavorite(item);
  store.toggleFavorite(item);
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    duration: const Duration(milliseconds: 1600),
    content: Text(was ? t('Removed from favorites') : t('Added to favorites')),
  ));
}

/// Focusable, tappable wrapper with a visible focus ring (works with touch, mouse and TV remote).
/// With [onLongPress] the remote's OK key separates tap (on release) from hold.
class Pressable extends StatefulWidget {
  final Widget child;
  final TapCb? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.radius = 14});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  final FocusNode _node = FocusNode();
  bool _focused = false;
  late final SelectKeyHandler _keys = SelectKeyHandler(
    onTap: () => unawaited(_activate()),
    onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(),
  );

  @override
  void dispose() {
    _node.dispose();
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
    final ink = InkWell(
      focusNode: _node,
      onTap: widget.onTap == null ? null : () => unawaited(_activate()),
      onLongPress: widget.onLongPress,
      borderRadius: r,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      },
      child: AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          foregroundDecoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(
                color: _focused ? Pal.of(context).focus : Colors.transparent,
                width: 3),
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.onLongPress == null) {
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        },
        child: ink,
      );
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) => _keys.handle(e),
      child: ink,
    );
  }
}

class ArtPlaceholder extends StatelessWidget {
  final Item item;
  const ArtPlaceholder({super.key, required this.item});

  double get _hue {
    var h = 5381;
    for (final c in item.name.codeUnits) {
      h = ((h * 33) + c) & 0x7fffffff;
    }
    return (h % 360).toDouble();
  }

  String get _label {
    if (item.kind == Kind.live) {
      final words =
          item.displayTitle.split(' ').where((w) => w.isNotEmpty).take(2);
      return words.map((w) => w.substring(0, 1)).join().toUpperCase();
    }
    return item.displayTitle;
  }

  @override
  Widget build(BuildContext context) {
    final live = item.kind == Kind.live;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSVColor.fromAHSV(1, _hue, 0.55, 0.5).toColor(),
            HSVColor.fromAHSV(1, (_hue + 30) % 360, 0.6, 0.22).toColor(),
          ],
        ),
      ),
      alignment: Alignment.center,
      padding: EdgeInsets.all(live ? 4 : 10),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        maxLines: live ? 1 : 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontWeight: live ? FontWeight.w800 : FontWeight.w700,
          fontSize: live ? 18 : 12,
        ),
      ),
    );
  }
}

class ArtThumb extends StatefulWidget {
  final Item item;
  final bool fit;
  final int cacheWidth;
  const ArtThumb(
      {super.key, required this.item, this.fit = false, this.cacheWidth = 400});

  @override
  State<ArtThumb> createState() => _ArtThumbState();
}

class _ArtThumbState extends State<ArtThumb> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtThumb old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id) {
      _resolved = null;
      _load();
    }
  }

  Future<void> _load() async {
    final it = widget.item;
    if (it.logo != null) return;
    final r = await ArtworkService.instance.artwork(it);
    if (mounted && widget.item.id == it.id && r != null) {
      setState(() => _resolved = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.item.logo ?? _resolved;
    final placeholder = ArtPlaceholder(item: widget.item);
    if (url == null) return placeholder;
    return Image.network(
      url,
      fit: widget.fit ? BoxFit.contain : BoxFit.cover,
      cacheWidth: widget.cacheWidth,
      frameBuilder: (ctx, child, frame, sync) {
        if (frame == null && !sync) return placeholder;
        if (widget.fit) {
          return Container(
              color: Pal.current.surface,
              padding: const EdgeInsets.all(6),
              child: child);
        }
        return child;
      },
      errorBuilder: (ctx, e, s) => placeholder,
    );
  }
}

class BadgeRow extends StatelessWidget {
  final Item item;
  const BadgeRow({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final y = item.year;
    final p = Pal.of(context);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (y != null)
          Text(y,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.muted)),
        for (final b in item.badges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: p.text.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(b,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  final Item item;
  final TapCb onTap;
  final VoidCallback? onLongPress;
  final double? width;
  const PosterCard(
      {super.key,
      required this.item,
      required this.onTap,
      this.onLongPress,
      this.width});

  @override
  Widget build(BuildContext context) {
    final live = item.kind == Kind.live;
    final frac = live ? null : store.resumeFraction(item.id);
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: live ? 1.6 : 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArtThumb(item: item, fit: live),
                if (frac != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 4,
                      backgroundColor: Colors.black54,
                      color: kBrand,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
      ],
    );
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: width == null ? card : SizedBox(width: width, child: card),
    );
  }
}

class Shelf extends StatelessWidget {
  final String title;
  final List<Item> items;
  final Object? Function(Item) onOpen;
  const Shelf(
      {super.key,
      required this.title,
      required this.items,
      required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scale = isWide(context) ? 1.35 : 1.0;
    final live = items.first.kind == Kind.live;
    final w = (live ? 180.0 : 124.0) * scale;
    final h = (live ? 162.0 : 244.0) * scale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => PosterCard(
                  item: items[i], width: w, onTap: () => onOpen(items[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class HeroBanner extends StatelessWidget {
  final Item item;
  final VoidCallback onPlay;
  const HeroBanner({super.key, required this.item, required this.onPlay});

  String get _label {
    switch (item.kind) {
      case Kind.live:
        return t('Live');
      case Kind.movie:
        return t('Movies');
      case Kind.series:
        return t('Series');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final live = item.kind == Kind.live;
    final height = isWide(context) ? 460.0 : 380.0;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  p.accent.withValues(alpha: 0.6),
                  p.bg,
                ],
              ),
            ),
          ),
          if (live)
            Align(
              alignment: const Alignment(0, -0.35),
              child: SizedBox(
                width: 240,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ArtThumb(item: item, fit: true),
                ),
              ),
            )
          else
            ArtThumb(item: item, cacheWidth: 900),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [p.bg.withValues(alpha: 0), p.bg.withValues(alpha: 0.92)],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: p.muted)),
                const SizedBox(height: 4),
                Text(item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w800, color: p.text)),
                const SizedBox(height: 6),
                BadgeRow(item: item),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onPlay,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(t('Play'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) => IconButton.filledTonal(
                        onPressed: () => store.toggleFavorite(item),
                        icon: Icon(
                            store.isFavorite(item) ? Icons.check : Icons.add),
                      ),
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
