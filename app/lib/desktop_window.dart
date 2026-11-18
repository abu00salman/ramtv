import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Window control on Windows/macOS/Linux. Full screen covers the whole app
/// window, so the player's own controls (seek, aspect, channels) stay usable.
class DesktopWindow {
  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static bool _fullScreen = false;
  static bool get isFullScreen => _fullScreen;

  static Future<void> init() async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'RaM tv',
      minimumSize: Size(960, 540),
      backgroundColor: Colors.black,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      // Open filling the screen on Windows (taskbar stays visible until full screen).
      if (Platform.isWindows) await windowManager.maximize();
      await windowManager.focus();
    });
  }

  static Future<void> setFullScreen(bool value) async {
    if (!supported) return;
    _fullScreen = value;
    await windowManager.setFullScreen(value);
  }

  static Future<void> toggleFullScreen() async {
    if (!supported) return;
    await setFullScreen(!await windowManager.isFullScreen());
  }
}
