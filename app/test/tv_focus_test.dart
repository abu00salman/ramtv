import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/ui/tv.dart';

void main() {
  testWidgets('TvFocusable shows focus, activates with select and keeps focus afterwards',
      (tester) async {
    var taps = 0;
    final node = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: TvFocusable(
              focusNode: node,
              onTap: () async {
                taps++;
                await Future<void>.delayed(const Duration(milliseconds: 50));
              },
              builder: (c, focused) => Text(focused ? 'focused' : 'idle'),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('idle'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(find.text('focused'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, 1);
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    node.dispose();
  });

  testWidgets('tvScale is proportional to the screen height', (tester) async {
    late double scale;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Builder(builder: (context) {
      scale = tvScale(context);
      return const SizedBox.shrink();
    }));
    expect(scale, closeTo(1.0, 0.001));
  });
}
