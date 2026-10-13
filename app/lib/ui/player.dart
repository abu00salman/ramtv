import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../store.dart';
import '../strings.dart';
import '../text_utils.dart';
import '../playback_queue.dart';
import '../epg.dart';
import '../perf.dart';
import 'package:http/http.dart' as http;
import 'widgets.dart';

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

  final FocusNode _rootFocus = FocusNode();
  final FocusNode _playFocus = FocusNode();
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _hudTimer;
  Timer? _reconnectTimer;
  Timer? _healthyTimer;

  bool _playing = false;
  bool _buffering = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
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

  BoxFit _fit = BoxFit.contain;
  double _rate = 1.0;
  double _volume = 100;
  double? _dragValue;
  double _tapX = 0;
  String? _hud;

  @override
  void initState() {
    super.initState();
    req = widget.req;
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
      if (p > _position && _message != null && !_failed) _message = null;
      _position = p;
      _saveResume();
      if (_controlsVisible && mounted) setState(() {});
    }));
    _subs.add(player.stream.completed.listen((c) {
      if (c) _onCompleted();
    }));
    _subs.add(player.stream.error.listen((e) {
      _onError(e);
    }));

    _open(req);
    _restartHide();
  }

  void _updateDuration(Duration d) {
    if (_opening || !mounted) return;
    _duration = d;
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
    if (mounted) setState(() {});
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
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _reconnectTimer?.cancel();
    _healthyTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    WakelockPlus.disable();
    _rootFocus.dispose();
    _playFocus.dispose();
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
    _lastBucket = -1;
    _retries = 0;
    _failed = false;
    _message = null;
    _position = Duration.zero;
    _duration = Duration.zero;
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
          await player.stop();
          if (!_operations.isCurrent(generation)) return;
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
    if (key == null || req.isLive || !_resumed || _duration.inSeconds <= 0)
      return;
    final b = _position.inSeconds ~/ 5;
    if (b != _lastBucket) {
      _lastBucket = b;
      store.saveResume(
          key, _position.inSeconds.toDouble(), _duration.inSeconds.toDouble());
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
      if (mounted) {
        setState(() {
          _failed = true;
          _message = t(
              'Stream unavailable. Check your connection or try another channel.');
        });
      }
      return;
    }
    _retries++;
    if (mounted) {
      setState(() {
        _failed = false;
        _message = '${t('Reconnecting')}... ($_retries)';
      });
    }
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

  void _seekBy(int seconds) {
    if (req.isLive) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    player.seek(target);
    _flash(seconds < 0 ? '« ${-seconds}s' : '${seconds}s »');
  }

  void _flash(String text) {
    _hud = text;
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = null);
    });
    if (mounted) setState(() {});
  }

  void _setVolume(double v) {
    _volume = v.clamp(0.0, 100.0);
    player.setVolume(_volume);
    _flash('${_volume.round()}%');
  }

  // ------------------------------------------------------------ controls visibility

  void _showControls() {
    setState(() => _controlsVisible = true);
    _restartHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _playFocus.requestFocus();
    });
  }

  void _hideControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = false);
    _rootFocus.requestFocus();
  }

  void _restartHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && _controlsVisible) _hideControls();
    });
  }

  // ------------------------------------------------------------ keyboard / remote

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      _togglePlayback();
      _showControls();
      return KeyEventResult.handled;
    }
    if (_controlsVisible) {
      _restartHide();
      if (k == LogicalKeyboardKey.escape) {
        _hideControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (req.isLive) {
        _showControls();
      } else {
        _seekBy(-10);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (req.isLive) {
        _showControls();
      } else {
        _seekBy(10);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (req.isLive && store.canStep) {
        _zap(1);
      } else {
        _showControls();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (req.isLive && store.canStep) {
        _zap(-1);
      } else {
        _showControls();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _showControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ UI

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _trackLabel(String id, String? title, String? language) {
    final parts = <String>[];
    if (title != null && title.isNotEmpty) parts.add(title);
    if (language != null && language.isNotEmpty) parts.add(language);
    return parts.isEmpty ? id : parts.join(' · ');
  }

  Future<void> _openChannelList() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          itemCount: store.queue.length,
          itemBuilder: (_, i) {
            final item = store.queue[i];
            final current = item.id == req.item?.id;
            return ListTile(
              autofocus: current,
              leading: SizedBox(
                width: 56,
                height: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ArtThumb(item: item, fit: true),
                ),
              ),
              title: Text(item.displayTitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: current
                  ? const Icon(Icons.play_arrow_rounded, color: kBrand)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                final r = store.jump(item);
                if (r != null) _open(r);
              },
            );
          },
        ),
      ),
    );
    if (mounted) _showControls();
  }

  Future<void> _openProgramGuide() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ListView.builder(
          itemCount: _programs.length,
          itemBuilder: (_, index) {
            final program = _programs[index];
            final current = program.isCurrent(DateTime.now());
            final start =
                TimeOfDay.fromDateTime(program.start.toLocal()).format(context);
            final end =
                TimeOfDay.fromDateTime(program.end.toLocal()).format(context);
            return ListTile(
              autofocus: current || index == 0,
              focusColor: kBrand.withValues(alpha: 0.25),
              onTap: () => Navigator.of(context).pop(),
              leading: Icon(
                  current ? Icons.play_arrow_rounded : Icons.schedule_rounded),
              title: Text(program.title),
              subtitle: Text('$start – $end'),
            );
          },
        ),
      ),
    );
    if (mounted) _showControls();
  }

  Widget _controls(VideoState state) {
    final live = req.isLive;
    final maxMs = _duration.inMilliseconds.toDouble();
    final posMs = (_dragValue ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    final width = MediaQuery.of(context).size.width;
    final currentPrograms = _programs.where((p) => p.isCurrent(DateTime.now()));
    final program = currentPrograms.isEmpty ? null : currentPrograms.first;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _controlsVisible ? _hideControls() : _showControls(),
            onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
            onDoubleTap: () {
              final desktop = defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.macOS ||
                  defaultTargetPlatform == TargetPlatform.linux;
              if (desktop) {
                toggleFullscreen(state.context);
              } else {
                _seekBy(_tapX < width / 2 ? -10 : 10);
              }
            },
            onVerticalDragUpdate: (d) {
              if (d.localPosition.dx > width / 2)
                _setVolume(_volume - d.delta.dy / 2);
            },
          ),
        ),
        if (_buffering || _message != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_failed)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  if (!_failed && _message != null) const SizedBox(width: 10),
                  if (_message != null)
                    Flexible(
                      child: Text(_message!,
                          style: TextStyle(
                              color: _failed ? Colors.redAccent : Colors.white,
                              fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        if (_hud != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14)),
              child: Text(_hud!,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        if (_controlsVisible) ...[
          // top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      if (store.canStep) ...[
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: () => _zap(-1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: () => _zap(1),
                        ),
                      ],
                      if (live && store.queue.length > 1)
                        IconButton(
                          icon: const Icon(Icons.format_list_bulleted_rounded),
                          onPressed: _openChannelList,
                        ),
                      if (live && _programs.isNotEmpty)
                        IconButton(
                          tooltip: t('Program guide'),
                          icon: const Icon(Icons.view_list_rounded),
                          onPressed: _openProgramGuide,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            program == null
                                ? req.title
                                : '${req.title}\n${t('Now')}: ${program.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Listener(
              onPointerDown: (_) => _restartHide(),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!live && maxMs > 0)
                          Row(
                            children: [
                              Text(_fmt(_position),
                                  style: const TextStyle(fontSize: 12)),
                              Expanded(
                                child: Slider(
                                  value: posMs,
                                  min: 0,
                                  max: maxMs,
                                  onChanged: (v) =>
                                      setState(() => _dragValue = v),
                                  onChangeEnd: (v) {
                                    player.seek(
                                        Duration(milliseconds: v.round()));
                                    setState(() => _dragValue = null);
                                  },
                                ),
                              ),
                              Text(_fmt(_duration),
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          )
                        else if (live)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              children: const [
                                Icon(Icons.circle, size: 9, color: Colors.red),
                                SizedBox(width: 6),
                                Text('LIVE',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                _tracksMenu(),
                                _aspectMenu(),
                              ],
                            ),
                            Row(
                              children: [
                                if (!live)
                                  IconButton(
                                    iconSize: 30,
                                    icon: const Icon(Icons.replay_10_rounded),
                                    onPressed: () => _seekBy(-10),
                                  ),
                                IconButton(
                                  focusNode: _playFocus,
                                  iconSize: 46,
                                  icon: Icon(_playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded),
                                  onPressed: _togglePlayback,
                                ),
                                if (!live)
                                  IconButton(
                                    iconSize: 30,
                                    icon: const Icon(Icons.forward_10_rounded),
                                    onPressed: () => _seekBy(10),
                                  ),
                              ],
                            ),
                            Row(
                              children: [
                                if (!live) _speedMenu(),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen_rounded),
                                  onPressed: () =>
                                      toggleFullscreen(state.context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tracksMenu() {
    final tracks = player.state.tracks;
    return PopupMenuButton<dynamic>(
      icon: const Icon(Icons.subtitles_rounded),
      tooltip: '${t('Audio')} / ${t('Subtitles')}',
      onSelected: (v) {
        if (v is AudioTrack) player.setAudioTrack(v);
        if (v is SubtitleTrack) player.setSubtitleTrack(v);
      },
      itemBuilder: (_) => [
        PopupMenuItem<dynamic>(
          enabled: false,
          child: Text(t('Audio'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final a in tracks.audio)
          PopupMenuItem<dynamic>(
              value: a, child: Text(_trackLabel(a.id, a.title, a.language))),
        PopupMenuItem<dynamic>(
          enabled: false,
          child: Text(t('Subtitles'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final s in tracks.subtitle)
          PopupMenuItem<dynamic>(
              value: s, child: Text(_trackLabel(s.id, s.title, s.language))),
      ],
    );
  }

  Widget _aspectMenu() {
    return PopupMenuButton<BoxFit>(
      icon: const Icon(Icons.aspect_ratio_rounded),
      tooltip: t('Aspect'),
      onSelected: (v) => setState(() => _fit = v),
      itemBuilder: (_) => [
        PopupMenuItem(value: BoxFit.contain, child: Text(t('Fit'))),
        PopupMenuItem(value: BoxFit.cover, child: Text(t('Fill'))),
        PopupMenuItem(value: BoxFit.fill, child: Text(t('Stretch'))),
      ],
    );
  }

  Widget _speedMenu() {
    return PopupMenuButton<double>(
      icon: const Icon(Icons.speed_rounded),
      tooltip: t('Speed'),
      onSelected: (v) {
        _rate = v;
        player.setRate(v);
        setState(() {});
      },
      itemBuilder: (_) => [
        for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem<double>(
              value: r, child: Text('${r}x${r == _rate ? '  ✓' : ''}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: !_controlsVisible,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _controlsVisible) _hideControls();
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Video(
            controller: controller,
            fit: _fit,
            fill: Colors.black,
            controls: _controls,
          ),
        ),
      ),
    );
  }
}
