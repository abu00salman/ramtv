import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../epg.dart';
import '../models.dart';
import '../perf.dart';
import '../playback_queue.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';
import '../theme.dart';
import 'dpad.dart';
import 'widgets.dart';

enum _Aspect { fit, fill, original, stretch }

enum _Menu { audio, subtitle, quality, aspect, speed, guide }

enum _BrowseSet { all, favorites, recent }

BoxFit _fitOf(_Aspect a) {
  switch (a) {
    case _Aspect.fit:
      return BoxFit.contain;
    case _Aspect.fill:
      return BoxFit.cover;
    case _Aspect.original:
      return BoxFit.scaleDown;
    case _Aspect.stretch:
      return BoxFit.fill;
  }
}

class _Opt {
  final String label;
  final bool selected;
  final VoidCallback onPick;
  const _Opt(this.label, this.selected, this.onPick);
}

class PlayerScreen extends StatefulWidget {
  final PlayRequest req;
  const PlayerScreen({super.key, required this.req});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;
  late PlayRequest req;
  final GlobalKey _videoKey = GlobalKey();
  VideoState? _videoState;

  final FocusNode _rootFocus = FocusNode();
  final Map<String, FocusNode> _nodes = {};
  final List<StreamSubscription<dynamic>> _subs = [];

  // Progress is kept in notifiers so the whole player is not rebuilt on every tick.
  final ValueNotifier<Duration> _posN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durN = ValueNotifier(Duration.zero);
  final ValueNotifier<String?> _hudN = ValueNotifier(null);

  bool _controlsVisible = true;
  _Menu? _menu;
  String _menuReturn = 'play';
  bool _browsing = false;
  Timer? _hideTimer;
  Timer? _hudTimer;
  Timer? _reconnectTimer;
  Timer? _healthyTimer;
  Timer? _seekTimer;
  Timer? _epgTicker;

  bool _playing = false;
  bool _buffering = true;
  String? _message;
  bool _failed = false;
  int _retries = 0;
  bool _resumed = false;
  int _lastBucket = -1;
  final PlaybackQueue _operations = PlaybackQueue();
  int _generation = 0;
  bool _opening = false;
  http.Client? _epgClient;
  List<EpgProgram> _programs = [];
  bool _prefsApplied = false;

  _Aspect _aspect = _Aspect.fit;
  double _rate = 1.0;
  int _pendingSeek = 0;
  int _seekRepeat = 0;
  double _tapX = 0;

  // channel browser
  _BrowseSet _browseSet = _BrowseSet.all;
  String? _browseGroup;
  bool _searching = false;
  final TextEditingController _query = TextEditingController();
  ScrollController? _browseScroll;
  final FocusNode _browseFocus = FocusNode(debugLabel: 'browse-entry');

  FocusNode _n(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: id));

  @override
  void initState() {
    super.initState();
    req = widget.req;
    final saved = store.prefs.getString('pref.aspect');
    _aspect = _Aspect.values
        .firstWhere((a) => a.name == saved, orElse: () => _Aspect.fit);
    player = Player();
    controller = VideoController(player);
    WakelockPlus.enable();

    _subs.add(player.stream.playing.listen((v) {
      _playing = v;
      if (v && !_buffering && !_opening) Perf.firstFrame();
      _trackHealth();
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.buffering.listen((v) {
      _buffering = v;
      if (v) {
        Perf.rebuffer();
      } else if (_playing && !_opening) {
        Perf.firstFrame();
      }
      _trackHealth();
      if (mounted) setState(() {});
    }));
    _subs.add(player.stream.duration.listen(_updateDuration));
    _subs.add(player.stream.position.listen((p) {
      if (_opening) return;
      if (p > _posN.value && _message != null && !_failed) {
        _message = null;
        if (mounted) setState(() {});
      }
      _posN.value = p;
      _saveResume();
    }));
    _subs.add(player.stream.completed.listen((c) {
      if (c) _onCompleted();
    }));
    _subs.add(player.stream.error.listen(_onError));
    _subs.add(player.stream.tracks.listen((tracks) {
      _applyTrackPrefs(tracks);
      if (mounted) setState(() {});
    }));

    _epgTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && req.isLive && _programs.isNotEmpty) setState(() {});
    });
    _open(req);
    _restartHide();
  }

  void _updateDuration(Duration d) {
    if (_opening || !mounted) return;
    _durN.value = d;
    if (!_resumed && d > Duration.zero) {
      _resumed = true;
      final key = req.resumeKey;
      if (key != null) {
        final r = store.getResume(key);
        if (r != null && r.length == 2 && r[0] > 20) {
          player.seek(Duration(seconds: (r[0] - 3).round()));
        }
      }
    }
    setState(() {});
  }

  void _trackHealth() {
    if (_opening || !_playing || _buffering) {
      _healthyTimer?.cancel();
      _healthyTimer = null;
      return;
    }
    final generation = _generation;
    _healthyTimer ??= Timer(const Duration(seconds: 30), () {
      _healthyTimer = null;
      if (mounted && _operations.isCurrent(generation)) _retries = 0;
    });
  }

  @override
  void dispose() {
    _epgClient?.close();
    for (final t in [
      _hideTimer,
      _hudTimer,
      _reconnectTimer,
      _healthyTimer,
      _seekTimer,
      _epgTicker
    ]) {
      t?.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    WakelockPlus.disable();
    _rootFocus.dispose();
    _browseFocus.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    _browseScroll?.dispose();
    _query.dispose();
    _posN.dispose();
    _durN.dispose();
    _hudN.dispose();
    unawaited(_operations.close(player.dispose));
    super.dispose();
  }

  // ------------------------------------------------------------ playback

  Future<void> _open(PlayRequest r) async {
    Perf.openStart();
    _saveResume();
    _reconnectTimer?.cancel();
    _healthyTimer?.cancel();
    _healthyTimer = null;
    _generation = _operations.invalidate();
    req = r;
    _epgClient?.close();
    _programs = [];
    if (r.isLive && r.item != null) {
      final client = http.Client();
      _epgClient = client;
      unawaited(_loadEpg(r, _generation, client));
    }
    _resumed = false;
    _prefsApplied = false;
    _lastBucket = -1;
    _retries = 0;
    _failed = false;
    _message = null;
    _posN.value = Duration.zero;
    _durN.value = Duration.zero;
    _buffering = true;
    if (mounted) setState(() {});
    await _openMedia(r, _generation);
  }

  Future<void> _loadEpg(
      PlayRequest request, int generation, http.Client client) async {
    try {
      final programs = await store.epg(request.item!, client: client);
      if (mounted && _operations.isCurrent(generation)) {
        setState(() => _programs = programs);
      }
    } catch (_) {
      // Optional metadata must never prevent playback.
    } finally {
      client.close();
      if (identical(_epgClient, client)) _epgClient = null;
    }
  }

  Future<void> _openMedia(PlayRequest r, int generation) async {
    try {
      await _operations.run(generation, () async {
        _opening = true;
        try {
          await player.open(
            Media(r.url, httpHeaders: const {'User-Agent': 'RaMtv/1.0'}),
            play: true,
          );
        } finally {
          _opening = false;
        }
        if (_operations.isCurrent(generation) && mounted) {
          _updateDuration(player.state.duration);
          _playing = player.state.playing;
          _buffering = player.state.buffering;
          _trackHealth();
        }
      });
    } catch (_) {
      if (mounted && _operations.isCurrent(generation)) {
        _onError(
            'Stream unavailable. Check your connection or try another channel.');
      }
    }
  }

  void _saveResume() {
    final key = req.resumeKey;
    final dur = _durN.value;
    if (key == null || req.isLive || !_resumed || dur.inSeconds <= 0) return;
    final pos = _posN.value;
    final b = pos.inSeconds ~/ 5;
    if (b != _lastBucket) {
      _lastBucket = b;
      store.saveResume(key, pos.inSeconds.toDouble(), dur.inSeconds.toDouble());
    }
  }

  void _onCompleted() {
    if (_opening) return;
    if (req.isLive) {
      _scheduleReconnect();
      return;
    }
    final key = req.resumeKey;
    if (key != null) store.clearResume(key);
    if (req.isEpisode) _zap(1);
  }

  void _onError(String e) {
    Perf.error();
    if (req.isLive) {
      _scheduleReconnect();
    } else if (mounted) {
      setState(() {
        _failed = true;
        _message = t(
            'Stream unavailable. Check your connection or try another channel.');
      });
    }
  }

  void _scheduleReconnect() {
    if (!mounted || !_operations.isCurrent(_generation)) return;
    _healthyTimer?.cancel();
    _healthyTimer = null;
    if (_reconnectTimer?.isActive ?? false) return;
    if (_retries >= 6) {
      setState(() {
        _failed = true;
        _message = t(
            'Stream unavailable. Check your connection or try another channel.');
      });
      return;
    }
    _retries++;
    setState(() {
      _failed = false;
      _message = '${t('Reconnecting')}... ($_retries/6)';
    });
    final generation = _generation;
    final request = req;
    _reconnectTimer = Timer(reconnectDelay(_retries), () {
      _reconnectTimer = null;
      if (!mounted || !_operations.isCurrent(generation)) return;
      unawaited(_openMedia(request, generation));
    });
  }

  void _zap(int delta) {
    final r = store.zap(delta);
    if (r != null) _open(r);
  }

  void _togglePlayback() {
    if (_failed) {
      unawaited(_open(req));
    } else {
      unawaited(player.playOrPause());
    }
  }

  // ------------------------------------------------------------ seeking (movies / series only)

  bool get _canSeek => !req.isLive && _durN.value > Duration.zero;

  void _seekTo(Duration target) {
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    final d = _durN.value;
    if (d > Duration.zero && t > d) t = d;
    player.seek(t);
  }

  /// Accumulates steps while a key is held (10s, then 30s, 60s, 120s) and applies them in one seek.
  void _seekAccumulate(int sign, {required bool repeat}) {
    if (!_canSeek) return;
    _seekRepeat = repeat ? _seekRepeat + 1 : 0;
    final step = _seekRepeat > 16
        ? 120
        : (_seekRepeat > 8 ? 60 : (_seekRepeat > 3 ? 30 : 10));
    _pendingSeek += sign * step;
    _flash('${_pendingSeek > 0 ? '+' : ''}$_pendingSeek s');
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 220), () {
      final delta = _pendingSeek;
      _pendingSeek = 0;
      _seekRepeat = 0;
      _seekTo(_posN.value + Duration(seconds: delta));
    });
  }

  void _flash(String text) {
    _hudN.value = text;
    _hudTimer?.cancel();
    _hudTimer =
        Timer(const Duration(milliseconds: 900), () => _hudN.value = null);
  }

  // ------------------------------------------------------------ track preferences

  void _applyTrackPrefs(Tracks tracks) {
    if (_prefsApplied) return;
    final audioPref = store.prefs.getString('pref.audio');
    final subPref = store.prefs.getString('pref.sub');
    var any = false;
    if (audioPref != null) {
      for (final a in tracks.audio) {
        if (_trackKey(a.language, a.title) == audioPref) {
          player.setAudioTrack(a);
          any = true;
          break;
        }
      }
    }
    if (subPref != null) {
      if (subPref == 'off') {
        player.setSubtitleTrack(SubtitleTrack.no());
        any = true;
      } else {
        for (final s in tracks.subtitle) {
          if (_trackKey(s.language, s.title) == subPref) {
            player.setSubtitleTrack(s);
            any = true;
            break;
          }
        }
      }
    }
    if (tracks.audio.length > 2 || any) _prefsApplied = true;
  }

  String _trackKey(String? language, String? title) =>
      (language != null && language.isNotEmpty) ? language : (title ?? '');

  // ------------------------------------------------------------ controls visibility

  void _showControls({String focusId = 'play'}) {
    setState(() => _controlsVisible = true);
    _restartHide();
    _focusAfterBuild(focusId);
  }

  void _focusAfterBuild(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = _n(id);
      if (n.context != null) {
        n.requestFocus();
      } else {
        final play = _n('play');
        if (play.context != null) play.requestFocus();
      }
    });
  }

  void _hideControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = false);
    _rootFocus.requestFocus();
  }

  /// Controls stay visible while a sub-menu or the channel browser is open.
  void _restartHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted &&
          _playing &&
          _controlsVisible &&
          _menu == null &&
          !_browsing) {
        _hideControls();
      }
    });
  }

  // ------------------------------------------------------------ menus

  void _openMenu(_Menu m, String returnId) {
    _hideTimer?.cancel();
    setState(() {
      _menu = m;
      _menuReturn = returnId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu != null) _n('opt-first').requestFocus();
    });
  }

  void _closeMenu() {
    if (_menu == null) return;
    setState(() => _menu = null);
    _restartHide();
    _focusAfterBuild(_menuReturn);
  }

  List<_Opt> _menuOptions() {
    final tracks = player.state.tracks;
    final current = player.state.track;
    switch (_menu!) {
      case _Menu.audio:
        return [
          for (final a in tracks.audio)
            _Opt(_trackLabel(a.id, a.title, a.language),
                current.audio.id == a.id, () {
              player.setAudioTrack(a);
              store.prefs
                  .setString('pref.audio', _trackKey(a.language, a.title));
              _closeMenu();
            }),
        ];
      case _Menu.subtitle:
        return [
          for (final s in tracks.subtitle)
            _Opt(_trackLabel(s.id, s.title, s.language),
                current.subtitle.id == s.id, () {
              player.setSubtitleTrack(s);
              store.prefs.setString('pref.sub',
                  s.id == 'no' ? 'off' : _trackKey(s.language, s.title));
              _closeMenu();
            }),
        ];
      case _Menu.quality:
        return [
          for (final v
              in tracks.video.where((v) => v.id != 'auto' && v.id != 'no'))
            _Opt(v.h != null ? '${v.h}p' : v.id, current.video.id == v.id, () {
              player.setVideoTrack(v);
              _closeMenu();
            }),
        ];
      case _Menu.aspect:
        final labels = {
          _Aspect.fit: t('Fit'),
          _Aspect.fill: t('Fill'),
          _Aspect.original: t('Original'),
          _Aspect.stretch: t('Stretch'),
        };
        return [
          for (final a in _Aspect.values)
            _Opt(labels[a]!, _aspect == a, () {
              setState(() => _aspect = a);
              store.prefs.setString('pref.aspect', a.name);
              _closeMenu();
            }),
        ];
      case _Menu.speed:
        return [
          for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            _Opt('${r}x', _rate == r, () {
              _rate = r;
              player.setRate(r);
              _closeMenu();
            }),
        ];
      case _Menu.guide:
        final now = DateTime.now();
        return [
          for (final p in _programs)
            _Opt(
              '${_hm(p.start)} - ${_hm(p.end)}   ${p.title}',
              p.isCurrent(now),
              _closeMenu,
            ),
        ];
    }
  }

  String _hm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _menuTitle() {
    switch (_menu!) {
      case _Menu.audio:
        return t('Audio');
      case _Menu.subtitle:
        return t('Subtitles');
      case _Menu.quality:
        return t('Quality');
      case _Menu.aspect:
        return t('Aspect ratio');
      case _Menu.speed:
        return t('Speed');
      case _Menu.guide:
        return t('Program guide');
    }
  }

  String _trackLabel(String id, String? title, String? language) {
    if (id == 'no') return t('Off');
    if (id == 'auto') return t('Auto');
    final parts = <String>[];
    if (title != null && title.isNotEmpty) parts.add(title);
    if (language != null && language.isNotEmpty) parts.add(language);
    return parts.isEmpty ? id : parts.join(' · ');
  }

  // ------------------------------------------------------------ channel browser

  void _enterBrowse() {
    if (!req.isLive) return;
    _hideTimer?.cancel();
    final list = _browseItems();
    final idx = list.indexWhere((e) => e.id == req.item?.id);
    final s = uiScale(context);
    _browseScroll?.dispose();
    _browseScroll =
        ScrollController(initialScrollOffset: idx <= 2 ? 0 : (idx - 2) * 64 * s);
    setState(() {
      _browsing = true;
      _controlsVisible = false;
      _menu = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _browsing) _browseFocus.requestFocus();
    });
  }

  void _exitBrowse() {
    if (!_browsing) return;
    setState(() {
      _browsing = false;
      _searching = false;
      _query.clear();
    });
    _rootFocus.requestFocus();
  }

  List<Item> _browseItems() {
    Iterable<Item> src;
    switch (_browseSet) {
      case _BrowseSet.favorites:
        src = store.live.where((e) => store.favorites.contains(e.id));
        break;
      case _BrowseSet.recent:
        src = store.recents.where((e) => e.kind == Kind.live);
        break;
      case _BrowseSet.all:
        src = _browseGroup == null
            ? store.live
            : store.live.where((e) => e.group == _browseGroup);
        break;
    }
    final q = normalizeSearch(_query.text);
    if (q.isNotEmpty) {
      src = src.where((e) => searchKey(e).contains(q));
    }
    return src.toList();
  }

  void _confirmChannel(Item item, List<Item> list) {
    if (item.id == req.item?.id) {
      _exitBrowse();
      return;
    }
    final r = store.switchLive(item, list: list);
    _exitBrowse();
    if (r != null) _open(r);
  }

  void _previousChannel() {
    final prev = store.previousLive(req.item?.id);
    if (prev == null) return;
    final r = store.switchLive(prev);
    if (r != null) _open(r);
  }

  // ------------------------------------------------------------ back / keys

  void _onBack() {
    if (_menu != null) {
      _closeMenu();
    } else if (_browsing) {
      if (_searching) {
        setState(() {
          _searching = false;
          _query.clear();
        });
        _browseFocus.requestFocus();
      } else {
        _exitBrowse();
      }
    } else if (_controlsVisible) {
      _hideControls();
    } else {
      Navigator.of(context).pop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent) {
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        _seekRepeat = 0;
      }
      return KeyEventResult.ignored;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final repeat = e is KeyRepeatEvent;

    // Hardware media keys work in every state.
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      if (!repeat) _togglePlayback();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      player.play();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      player.pause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekAccumulate(1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekAccumulate(-1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.channelUp ||
        k == LogicalKeyboardKey.channelDown) {
      if (!repeat && req.isLive && store.canStep) {
        _zap(k == LogicalKeyboardKey.channelUp ? 1 : -1);
      }
      return KeyEventResult.handled;
    }

    // Menus and the channel browser own the arrows (focus traversal).
    if (_menu != null || _browsing) return KeyEventResult.ignored;

    if (_controlsVisible) {
      _restartHide();
      return KeyEventResult.ignored;
    }

    // Controls hidden: nothing changes the channel by accident.
    if (SelectKeyHandler.isSelect(k)) {
      if (!repeat) _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (!repeat) {
        if (req.isLive) {
          _enterBrowse();
        } else {
          _showControls();
        }
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (!repeat) _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      if (_canSeek) {
        final sign = k == LogicalKeyboardKey.arrowRight ? 1 : -1;
        _seekAccumulate(sign, repeat: repeat);
      } else if (!repeat) {
        _showControls();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ EPG helpers

  EpgProgram? get _nowProgram {
    final now = DateTime.now();
    for (final p in _programs) {
      if (p.isCurrent(now)) return p;
    }
    return null;
  }

  EpgProgram? get _nextProgram {
    final cur = _nowProgram;
    if (cur == null) return null;
    for (final p in _programs) {
      if (!p.start.isBefore(cur.end)) return p;
    }
    return null;
  }

  // ------------------------------------------------------------ UI

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  bool get _hasQuality =>
      player.state.tracks.video
          .where((v) => v.id != 'auto' && v.id != 'no')
          .length >
      1;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  Widget _captureVideoState(VideoState state) {
    _videoState = state;
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = uiScale(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: uiTextScaler()),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
          backgroundColor: _browsing ? p.bg : Colors.black,
          body: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: LayoutBuilder(builder: (context, c) {
              final size = Size(c.maxWidth, c.maxHeight);
              return _stage(p, s, size);
            }),
          ),
        ),
      ),
    );
  }

  Widget _stage(Palette p, double s, Size size) {
    final panelW = (size.width * 0.38).clamp(340.0, 640.0).toDouble();
    final gap = 24.0 * s;
    final winStart = panelW + gap * 2;
    final winW = size.width - winStart - gap;
    final winH = winW * 9 / 16;
    final winTop = 40.0 * s;

    final video = Stack(
      fit: StackFit.expand,
      children: [
        Video(
          key: _videoKey,
          controller: controller,
          fit: _browsing ? BoxFit.contain : _fitOf(_aspect),
          fill: Colors.black,
          controls: _captureVideoState,
        ),
        _statusOverlay(s),
        ValueListenableBuilder<String?>(
          valueListenable: _hudN,
          builder: (context, text, _) => text == null
              ? const SizedBox.shrink()
              : Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 22 * s, vertical: 12 * s),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14 * s)),
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 26 * s,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
        ),
      ],
    );

    return Stack(
      children: [
        AnimatedPositionedDirectional(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          start: _browsing ? winStart : 0,
          top: _browsing ? winTop : 0,
          width: _browsing ? winW : size.width,
          height: _browsing ? winH : size.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_browsing ? 16 * s : 0),
            child: video,
          ),
        ),
        if (!_browsing) Positioned.fill(child: _touchLayer(size)),
        if (_browsing) ...[
          PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: panelW,
              child: _browsePanel(p, s)),
          PositionedDirectional(
            start: winStart,
            end: gap,
            top: winTop + winH + 16 * s,
            child: _channelInfo(p, s),
          ),
        ],
        if (_controlsVisible && !_browsing) ..._controlsOverlay(p, s),
        if (_menu != null) _menuPanel(p, s),
      ],
    );
  }

  Widget _touchLayer(Size size) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_menu != null) {
          _closeMenu();
        } else if (_controlsVisible) {
          _hideControls();
        } else {
          _showControls();
        }
      },
      onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
      onDoubleTap: () {
        if (_isDesktop) {
          final st = _videoState;
          if (st != null) toggleFullscreen(st.context);
        } else if (_canSeek) {
          _seekAccumulate(_tapX < size.width / 2 ? -1 : 1, repeat: false);
        }
      },
    );
  }

  Widget _statusOverlay(double s) {
    if (!_buffering && _message == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: EdgeInsets.all(16 * s),
        constraints: BoxConstraints(maxWidth: 520 * s),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16 * s),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_failed)
                  SizedBox(
                      width: 24 * s,
                      height: 24 * s,
                      child: const CircularProgressIndicator(strokeWidth: 3)),
                if (!_failed && _message != null) SizedBox(width: 12 * s),
                if (_message != null)
                  Flexible(
                    child: Text(_message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _failed ? Colors.redAccent : Colors.white,
                            fontSize: 18 * s)),
                  ),
              ],
            ),
            if (_failed) ...[
              SizedBox(height: 12 * s),
              _PBtn(
                node: _n('retry'),
                icon: Icons.refresh_rounded,
                label: t('Retry'),
                s: s,
                accent: true,
                onTap: () => _open(req),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- controls overlay

  List<Widget> _controlsOverlay(Palette p, double s) {
    final live = req.isLive;
    final now = _nowProgram;
    final next = _nextProgram;
    final subtitle = live
        ? [
            if (now != null) '${t('Now')}: ${now.title}',
            if (next != null) '${t('Next')}: ${next.title}',
          ].join('   •   ')
        : '';
    return [
      PositionedDirectional(
        top: 0,
        start: 0,
        end: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(20 * s, 14 * s, 20 * s, 28 * s),
          child: Row(
            children: [
              _PBtn(
                node: _n('back'),
                icon: Icons.arrow_back_rounded,
                s: s,
                onTap: _onBack,
              ),
              SizedBox(width: 14 * s),
              if (live && req.item != null) ...[
                SizedBox(
                  width: 72 * s,
                  height: 46 * s,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10 * s),
                    child: ArtThumb(item: req.item!, fit: true),
                  ),
                ),
                SizedBox(width: 14 * s),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(req.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 26 * s,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17 * s, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      PositionedDirectional(
        bottom: 0,
        start: 0,
        end: 0,
        child: Listener(
          onPointerDown: (_) => _restartHide(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE6000000), Color(0x00000000)],
              ),
            ),
            padding: EdgeInsets.fromLTRB(28 * s, 40 * s, 28 * s, 18 * s),
            child: FocusTraversalGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _progressArea(p, s, now),
                  SizedBox(height: 10 * s),
                  _transportRow(s),
                  SizedBox(height: 10 * s),
                  _optionsRow(s),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _progressArea(Palette p, double s, EpgProgram? now) {
    if (req.isLive) {
      double? frac;
      if (now != null) {
        final total = now.end.difference(now.start).inSeconds;
        if (total > 0) {
          frac = (DateTime.now().difference(now.start).inSeconds / total)
              .clamp(0.0, 1.0);
        }
      }
      return Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
            decoration: BoxDecoration(
                color: const Color(0xFFE5233C),
                borderRadius: BorderRadius.circular(6 * s)),
            child: Text('LIVE',
                style: TextStyle(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          if (frac != null) ...[
            SizedBox(width: 14 * s),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4 * s),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 5 * s,
                  backgroundColor: Colors.white24,
                  color: p.accent,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      );
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: _durN,
      builder: (context, dur, _) => ValueListenableBuilder<Duration>(
        valueListenable: _posN,
        builder: (context, pos, _) {
          final total = dur.inMilliseconds;
          final frac =
              total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
          return Row(
            children: [
              Text(_fmt(pos),
                  style: TextStyle(fontSize: 16 * s, color: Colors.white)),
              SizedBox(width: 14 * s),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      if (total > 0) {
                        final f =
                            (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                        _seekTo(Duration(milliseconds: (total * f).round()));
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8 * s),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4 * s),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 6 * s,
                          backgroundColor: Colors.white24,
                          color: p.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 14 * s),
              Text(_fmt(dur),
                  style: TextStyle(fontSize: 16 * s, color: Colors.white70)),
            ],
          );
        },
      ),
    );
  }

  Widget _transportRow(double s) {
    final live = req.isLive;
    final prev = live ? store.previousLive(req.item?.id) : null;
    final seekOk = _canSeek;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!live && req.isEpisode && store.canStep) ...[
          _PBtn(
              node: _n('prev'),
              icon: Icons.skip_previous_rounded,
              s: s,
              onTap: () => _zap(-1)),
          SizedBox(width: 10 * s),
        ],
        if (live && prev != null) ...[
          _PBtn(
            node: _n('prevch'),
            icon: Icons.history_rounded,
            label: t('Previous channel'),
            s: s,
            onTap: _previousChannel,
          ),
          SizedBox(width: 10 * s),
        ],
        if (seekOk) ...[
          _PBtn(
            node: _n('rew'),
            icon: Icons.replay_10_rounded,
            s: s,
            onTap: () => _seekAccumulate(-1, repeat: false),
            onRepeat: (n) => _seekAccumulate(-1, repeat: true),
          ),
          SizedBox(width: 10 * s),
        ],
        _PBtn(
          node: _n('play'),
          icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          s: s,
          big: true,
          onTap: _togglePlayback,
        ),
        if (seekOk) ...[
          SizedBox(width: 10 * s),
          _PBtn(
            node: _n('fwd'),
            icon: Icons.forward_10_rounded,
            s: s,
            onTap: () => _seekAccumulate(1, repeat: false),
            onRepeat: (n) => _seekAccumulate(1, repeat: true),
          ),
        ],
        if (!live && req.isEpisode && store.canStep) ...[
          SizedBox(width: 10 * s),
          _PBtn(
              node: _n('next'),
              icon: Icons.skip_next_rounded,
              s: s,
              onTap: () => _zap(1)),
        ],
      ],
    );
  }

  Widget _optionsRow(double s) {
    final live = req.isLive;
    final tracks = player.state.tracks;
    final hasAudio =
        tracks.audio.where((a) => a.id != 'auto' && a.id != 'no').length > 1;
    final hasSubs = tracks.subtitle
        .where((a) => a.id != 'auto' && a.id != 'no')
        .isNotEmpty;
    final buttons = <Widget>[
      if (live && store.live.length > 1)
        _PBtn(
          node: _n('channels'),
          icon: Icons.view_sidebar_rounded,
          label: t('Channels'),
          s: s,
          onTap: _enterBrowse,
        ),
      if (live && _programs.isNotEmpty)
        _PBtn(
          node: _n('guide'),
          icon: Icons.view_list_rounded,
          label: t('Program guide'),
          s: s,
          active: _menu == _Menu.guide,
          onTap: () => _openMenu(_Menu.guide, 'guide'),
        ),
      if (hasAudio)
        _PBtn(
          node: _n('audio'),
          icon: Icons.volume_up_rounded,
          label: t('Audio'),
          s: s,
          active: _menu == _Menu.audio,
          onTap: () => _openMenu(_Menu.audio, 'audio'),
        ),
      if (hasSubs)
        _PBtn(
          node: _n('subs'),
          icon: Icons.subtitles_rounded,
          label: t('Subtitles'),
          s: s,
          active: _menu == _Menu.subtitle,
          onTap: () => _openMenu(_Menu.subtitle, 'subs'),
        ),
      if (_hasQuality)
        _PBtn(
          node: _n('quality'),
          icon: Icons.high_quality_rounded,
          label: t('Quality'),
          s: s,
          active: _menu == _Menu.quality,
          onTap: () => _openMenu(_Menu.quality, 'quality'),
        ),
      _PBtn(
        node: _n('aspect'),
        icon: Icons.aspect_ratio_rounded,
        label: t('Aspect ratio'),
        s: s,
        active: _menu == _Menu.aspect,
        onTap: () => _openMenu(_Menu.aspect, 'aspect'),
      ),
      if (!live)
        _PBtn(
          node: _n('speed'),
          icon: Icons.speed_rounded,
          label: t('Speed'),
          s: s,
          active: _menu == _Menu.speed,
          onTap: () => _openMenu(_Menu.speed, 'speed'),
        ),
      if (_isDesktop)
        _PBtn(
          node: _n('fullscreen'),
          icon: Icons.fullscreen_rounded,
          s: s,
          onTap: () {
            final st = _videoState;
            if (st != null) toggleFullscreen(st.context);
          },
        ),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8 * s,
      runSpacing: 8 * s,
      children: buttons,
    );
  }

  // ---------------------------------------------------------- sub-menu panel

  Widget _menuPanel(Palette p, double s) {
    final options = _menuOptions();
    return PositionedDirectional(
      end: 28 * s,
      bottom: 170 * s,
      width: 360 * s,
      child: Container(
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(18 * s),
          border: Border.all(color: p.border),
        ),
        padding: EdgeInsets.all(14 * s),
        child: FocusTraversalGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_menuTitle(),
                  style: TextStyle(
                      fontSize: 22 * s,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
              SizedBox(height: 10 * s),
              if (options.isEmpty)
                Padding(
                  padding: EdgeInsets.all(8 * s),
                  child: Text('-',
                      style: TextStyle(fontSize: 18 * s, color: p.muted)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 300 * s),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < options.length; i++)
                        _OptRow(
                          node: i == 0 ? _n('opt-first') : null,
                          opt: options[i],
                          s: s,
                          p: p,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- channel browser

  Widget _browsePanel(Palette p, double s) {
    final list = _browseItems();
    final groups = store.liveGroups.take(14).toList();
    final currentId = req.item?.id;
    final hasCurrent = list.any((e) => e.id == currentId);
    return Container(
      color: p.panel,
      padding: EdgeInsets.fromLTRB(18 * s, 18 * s, 18 * s, 0),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t('Channels'),
                      style: TextStyle(
                          fontSize: 28 * s,
                          fontWeight: FontWeight.w800,
                          color: p.text)),
                ),
                _SmallIcon(
                  icon: Icons.search_rounded,
                  s: s,
                  p: p,
                  active: _searching,
                  onTap: () => setState(() => _searching = !_searching),
                ),
              ],
            ),
            SizedBox(height: 10 * s),
            if (_searching)
              Padding(
                padding: EdgeInsets.only(bottom: 8 * s),
                child: DpadTextField(
                  controller: _query,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: t('Search'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
            SizedBox(
              height: 46 * s,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _BrowseChip(
                    label: t('All'),
                    selected:
                        _browseSet == _BrowseSet.all && _browseGroup == null,
                    s: s,
                    p: p,
                    onTap: () => setState(() {
                      _browseSet = _BrowseSet.all;
                      _browseGroup = null;
                    }),
                  ),
                  _BrowseChip(
                    label: t('Favorites'),
                    selected: _browseSet == _BrowseSet.favorites,
                    s: s,
                    p: p,
                    onTap: () =>
                        setState(() => _browseSet = _BrowseSet.favorites),
                  ),
                  _BrowseChip(
                    label: t('Recent'),
                    selected: _browseSet == _BrowseSet.recent,
                    s: s,
                    p: p,
                    onTap: () => setState(() => _browseSet = _BrowseSet.recent),
                  ),
                  for (final g in groups)
                    _BrowseChip(
                      label: g,
                      selected:
                          _browseSet == _BrowseSet.all && _browseGroup == g,
                      s: s,
                      p: p,
                      onTap: () => setState(() {
                        _browseSet = _BrowseSet.all;
                        _browseGroup = g;
                      }),
                    ),
                ],
              ),
            ),
            SizedBox(height: 8 * s),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(t('No channels'),
                          style: TextStyle(fontSize: 20 * s, color: p.muted)))
                  : ListView.builder(
                      controller: _browseScroll,
                      itemExtent: 64 * s,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final item = list[i];
                        final isCurrent = item.id == currentId;
                        final entry = isCurrent || (!hasCurrent && i == 0);
                        return _BrowseRow(
                          key: ValueKey(item.id),
                          node: entry ? _browseFocus : null,
                          item: item,
                          current: isCurrent,
                          s: s,
                          p: p,
                          onOk: () => _confirmChannel(item, list),
                          onLong: () => toggleFavoriteWithToast(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelInfo(Palette p, double s) {
    final item = req.item;
    final now = _nowProgram;
    final next = _nextProgram;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (item != null)
              SizedBox(
                width: 84 * s,
                height: 54 * s,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10 * s),
                  child: ArtThumb(item: item, fit: true),
                ),
              ),
            SizedBox(width: 14 * s),
            Expanded(
              child: Text(req.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 28 * s,
                      fontWeight: FontWeight.w800,
                      color: p.text)),
            ),
          ],
        ),
        if (now != null) ...[
          SizedBox(height: 12 * s),
          Text('${t('Now')}: ${now.title}  (${_hm(now.start)} - ${_hm(now.end)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 19 * s, color: p.text)),
        ],
        if (next != null)
          Text('${t('Next')}: ${next.title}  (${_hm(next.start)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17 * s, color: p.muted)),
        SizedBox(height: 14 * s),
        Text(t('OK to watch  -  hold OK for favorite  -  Back to close'),
            style: TextStyle(fontSize: 15 * s, color: p.muted)),
      ],
    );
  }
}

// ---------------------------------------------------------------- widgets

/// Control button: strong white focus ring, filled accent when its menu is open.
class _PBtn extends StatefulWidget {
  final FocusNode node;
  final IconData icon;
  final String? label;
  final double s;
  final bool big;
  final bool active;
  final bool accent;
  final VoidCallback onTap;
  final void Function(int repeats)? onRepeat;

  const _PBtn({
    required this.node,
    required this.icon,
    required this.s,
    required this.onTap,
    this.label,
    this.big = false,
    this.active = false,
    this.accent = false,
    this.onRepeat,
  });

  @override
  State<_PBtn> createState() => _PBtnState();
}

class _PBtnState extends State<_PBtn> {
  bool _focused = false;
  late final SelectKeyHandler _keys = SelectKeyHandler(
    onTap: () => widget.onTap(),
    onRepeat: widget.onRepeat == null ? null : (n) => widget.onRepeat!(n),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = Pal.of(context);
    final size = (widget.big ? 68 : 54) * s;
    final filled = widget.active || widget.accent;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, e) => _keys.handle(e),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? p.accent
                    : (_focused
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.10)),
                border: Border.all(
                    color: _focused ? Colors.white : Colors.transparent,
                    width: 3 * s),
              ),
              child: Icon(widget.icon,
                  size: size * 0.55, color: filled ? p.onAccent : Colors.white),
            ),
            if (widget.label != null) ...[
              SizedBox(height: 4 * s),
              SizedBox(
                width: 110 * s,
                child: Text(widget.label!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14 * s,
                        fontWeight:
                            _focused ? FontWeight.w700 : FontWeight.w500,
                        color: _focused ? Colors.white : Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptRow extends StatefulWidget {
  final FocusNode? node;
  final _Opt opt;
  final double s;
  final Palette p;
  const _OptRow(
      {this.node, required this.opt, required this.s, required this.p});

  @override
  State<_OptRow> createState() => _OptRowState();
}

class _OptRowState extends State<_OptRow> {
  bool _focused = false;
  late final SelectKeyHandler _keys =
      SelectKeyHandler(onTap: () => widget.opt.onPick());

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = widget.p;
    final sel = widget.opt.selected;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 100), alignment: 0.5);
        }
      },
      onKeyEvent: (node, e) => _keys.handle(e),
      child: GestureDetector(
        onTap: widget.opt.onPick,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 2 * s),
          padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color:
                _focused ? p.text.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(12 * s),
            border: Border.all(
                color: _focused ? p.focus : Colors.transparent,
                width: 2.5 * s),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.opt.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20 * s,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? p.accent : p.text)),
              ),
              if (sel) Icon(Icons.check_rounded, size: 24 * s, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowseChip extends StatefulWidget {
  final String label;
  final bool selected;
  final double s;
  final Palette p;
  final VoidCallback onTap;
  const _BrowseChip(
      {required this.label,
      required this.selected,
      required this.s,
      required this.p,
      required this.onTap});

  @override
  State<_BrowseChip> createState() => _BrowseChipState();
}

class _BrowseChipState extends State<_BrowseChip> {
  bool _focused = false;
  late final SelectKeyHandler _keys =
      SelectKeyHandler(onTap: () => widget.onTap());

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = widget.p;
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 100), alignment: 0.5);
        }
      },
      onKeyEvent: (node, e) => _keys.handle(e),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: EdgeInsetsDirectional.only(end: 8 * s),
          padding: EdgeInsets.symmetric(horizontal: 18 * s),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected ? p.accent : p.surface,
            borderRadius: BorderRadius.circular(24 * s),
            border: Border.all(
                color: _focused ? p.focus : Colors.transparent,
                width: 2.5 * s),
          ),
          child: Text(widget.label,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 18 * s,
                  fontWeight: FontWeight.w600,
                  color: widget.selected ? p.onAccent : p.text)),
        ),
      ),
    );
  }
}

class _SmallIcon extends StatefulWidget {
  final IconData icon;
  final double s;
  final Palette p;
  final bool active;
  final VoidCallback onTap;
  const _SmallIcon(
      {required this.icon,
      required this.s,
      required this.p,
      required this.onTap,
      this.active = false});

  @override
  State<_SmallIcon> createState() => _SmallIconState();
}

class _SmallIconState extends State<_SmallIcon> {
  bool _focused = false;
  late final SelectKeyHandler _keys =
      SelectKeyHandler(onTap: () => widget.onTap());

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = widget.p;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, e) => _keys.handle(e),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46 * s,
          height: 46 * s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active ? p.accent : p.surface,
            border: Border.all(
                color: _focused ? p.focus : Colors.transparent,
                width: 2.5 * s),
          ),
          child: Icon(widget.icon,
              size: 26 * s, color: widget.active ? p.onAccent : p.text),
        ),
      ),
    );
  }
}

class _BrowseRow extends StatefulWidget {
  final FocusNode? node;
  final Item item;
  final bool current;
  final double s;
  final Palette p;
  final VoidCallback onOk;
  final VoidCallback onLong;
  const _BrowseRow({
    super.key,
    this.node,
    required this.item,
    required this.current,
    required this.s,
    required this.p,
    required this.onOk,
    required this.onLong,
  });

  @override
  State<_BrowseRow> createState() => _BrowseRowState();
}

class _BrowseRowState extends State<_BrowseRow> {
  bool _focused = false;
  late final SelectKeyHandler _keys = SelectKeyHandler(
    onTap: () => widget.onOk(),
    onLongPress: () => widget.onLong(),
  );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = widget.p;
    final fav = store.isFavorite(widget.item);
    return Focus(
      focusNode: widget.node,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 90), alignment: 0.5);
        }
      },
      onKeyEvent: (node, e) => _keys.handle(e),
      child: GestureDetector(
        onTap: widget.onOk,
        onLongPress: widget.onLong,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3 * s),
          padding: EdgeInsets.symmetric(horizontal: 10 * s),
          decoration: BoxDecoration(
            color: _focused
                ? p.text.withValues(alpha: 0.10)
                : (widget.current
                    ? p.accent.withValues(alpha: 0.16)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12 * s),
            border: Border.all(
                color: _focused ? p.focus : Colors.transparent,
                width: 2.5 * s),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64 * s,
                height: 40 * s,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8 * s),
                  child: ArtThumb(item: widget.item, fit: true),
                ),
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: Text(widget.item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20 * s,
                        fontWeight:
                            widget.current ? FontWeight.w800 : FontWeight.w500,
                        color: widget.current ? p.accent : p.text)),
              ),
              if (fav)
                Icon(Icons.favorite_rounded, size: 20 * s, color: p.accent),
              if (widget.current)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: 8 * s),
                  child: Icon(Icons.play_arrow_rounded,
                      size: 24 * s, color: p.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
