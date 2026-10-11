import 'package:flutter/material.dart';
import '../artwork.dart';
import '../models.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';

const Color kBrand = Color(0xFF0057FF);

bool isWide(BuildContext c) => MediaQuery.of(c).size.width >= 900;

/// Focusable, tappable wrapper with a visible focus ring (works with touch, mouse and TV remote).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  const Pressable({super.key, required this.child, this.onTap, this.radius = 14});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: r,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
        ),
        child: widget.child,
      ),
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
      final words = item.displayTitle.split(' ').where((w) => w.isNotEmpty).take(2);
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
          color: Colors.white.withOpacity(0.92),
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
  const ArtThumb({super.key, required this.item, this.fit = false});

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
      cacheWidth: 400,
      frameBuilder: (ctx, child, frame, sync) {
        if (frame == null && !sync) return placeholder;
        if (widget.fit) {
          return Container(
              color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(6), child: child);
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
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (y != null)
          Text(y, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
        for (final b in item.badges)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(b, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final double? width;
  const PosterCard({super.key, required this.item, required this.onTap, this.width});

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
      child: width == null ? card : SizedBox(width: width, child: card),
    );
  }
}

class Shelf extends StatelessWidget {
  final String title;
  final List<Item> items;
  final void Function(Item) onOpen;
  const Shelf({super.key, required this.title, required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scale = isWide(context) ? 1.35 : 1.0;
    final live = items.first.kind == Kind.live;
    final w = (live ? 180.0 : 124.0) * scale;
    final h = (live ? 150.0 : 232.0) * scale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  PosterCard(item: items[i], width: w, onTap: () => onOpen(items[i])),
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
                colors: [kBrand.withOpacity(0.6), const Color(0xFF0A0A0A)],
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
            ArtThumb(item: item),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEB000000)],
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white60)),
                const SizedBox(height: 4),
                Text(item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                BadgeRow(item: item),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onPlay,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(t('Play'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) => IconButton.filledTonal(
                        onPressed: () => store.toggleFavorite(item),
                        icon: Icon(store.isFavorite(item) ? Icons.check : Icons.add),
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
