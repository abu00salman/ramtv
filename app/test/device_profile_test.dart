import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/device_profile.dart';
import 'package:ramtv/ui/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DeviceProfile.isTelevision = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ramtv/device'), null);
  });

  testWidgets('Android TV uses television layout at 720p logical size',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('ramtv/device'), (_) async => true);
    await DeviceProfile.initialize();
    var wide = false;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(640, 360)),
        child: Builder(builder: (context) {
          wide = isWide(context);
          return const SizedBox.shrink();
        }),
      ),
    ));
    expect(wide, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
