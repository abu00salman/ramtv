import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uses Android's device mode rather than treating every large tablet as a TV.
class DeviceProfile {
  static bool isTelevision = false;

  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      isTelevision = await const MethodChannel('ramtv/device')
              .invokeMethod<bool>('isTelevision') ??
          false;
    } on MissingPluginException {
      // Older hosts and widget tests do not have the native bridge.
    } on PlatformException {
      // Preserve the regular responsive layout when detection is unavailable.
    }
  }
}
