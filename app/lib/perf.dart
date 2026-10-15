import 'dart:io';
import 'dart:ui' show FrameTiming, PlatformDispatcher;
import 'package:flutter/scheduler.dart';
import 'device_profile.dart';

/// Lightweight runtime measurements shown in Settings > Diagnostics.
/// Nothing sensitive is recorded (no URLs, names or credentials).
class Perf {
  static DateTime? _openAt;
  static bool _zap = false;
  static bool _marked = true;
  static int _opens = 0;
  static int rebuffers = 0;
  static int errors = 0;
  static final List<int> _ttff = [];
  static final List<int> _zapMs = [];
  static int _frames = 0;
  static double _frameSum = 0;
  static double worstFrame = 0;
  static int jank = 0;
  static bool _monitoring = false;

  static void startFrameMonitor() {
    if (_monitoring) return;
    _monitoring = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      _frames++;
      _frameSum += ms;
      if (ms > worstFrame) worstFrame = ms;
      if (ms > 33) jank++;
    }
  }

  static void openStart() {
    _zap = _opens > 0;
    _opens++;
    _openAt = DateTime.now();
    _marked = false;
  }

  static void firstFrame() {
    final at = _openAt;
    if (_marked || at == null) return;
    _marked = true;
    final ms = DateTime.now().difference(at).inMilliseconds;
    final list = _zap ? _zapMs : _ttff;
    list.add(ms);
    if (list.length > 50) list.removeAt(0);
  }

  static void rebuffer() {
    if (_marked) rebuffers++;
  }

  static void error() => errors++;

  static String _avg(List<int> l) => l.isEmpty
      ? '-'
      : '${(l.reduce((a, b) => a + b) / l.length).round()} ms  (n=${l.length})';

  static List<MapEntry<String, String>> report() {
    final view = PlatformDispatcher.instance.views.isEmpty
        ? null
        : PlatformDispatcher.instance.views.first;
    final size = view == null
        ? '-'
        : '${view.physicalSize.width.round()}x${view.physicalSize.height.round()} @${view.devicePixelRatio.toStringAsFixed(2)}x';
    final rss = (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0);
    return [
      MapEntry('Device', DeviceProfile.isTelevision ? 'Android TV' : Platform.operatingSystem),
      MapEntry('OS', Platform.operatingSystemVersion),
      MapEntry('Screen', size),
      MapEntry('Memory (RSS)', '$rss MB'),
      MapEntry('Time to first frame', _avg(_ttff)),
      MapEntry('Channel switch', _avg(_zapMs)),
      MapEntry('Rebuffering events', '$rebuffers'),
      MapEntry('Playback errors', '$errors'),
      MapEntry('UI frames', '$_frames'),
      MapEntry('UI frame avg', _frames == 0 ? '-' : '${(_frameSum / _frames).toStringAsFixed(1)} ms'),
      MapEntry('UI frame worst', '${worstFrame.toStringAsFixed(0)} ms'),
      MapEntry('Slow frames (>33 ms)', _frames == 0 ? '-' : '$jank  (${(jank * 100 / _frames).toStringAsFixed(1)}%)'),
    ];
  }

  static void reset() {
    _ttff.clear();
    _zapMs.clear();
    rebuffers = 0;
    errors = 0;
    _frames = 0;
    _frameSum = 0;
    worstFrame = 0;
    jank = 0;
  }
}
